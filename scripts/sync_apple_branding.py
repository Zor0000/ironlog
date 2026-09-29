#!/usr/bin/env python3
"""Keep the existing Apple app's editable metadata consistent with Setzo."""

import json
import os
import re
import subprocess


APP_ID = os.environ["ASC_APP_ID"]
PRIVACY_URL = "https://zor0000.github.io/setzo/privacy.html"
WEBSITE_URL = "https://zor0000.github.io/setzo/"
SUPPORT_URL = WEBSITE_URL + "support.html"
SUPPORT_EMAIL = "neerajcwork@gmail.com"
IOS_BUNDLE_ID = "com.parthjadhav.ironlog"


def asc(*args):
    result = subprocess.run(
        ["asc", *args, "--output", "json"],
        check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def resources(payload, resource_type):
    found = {}

    def visit(value):
        if isinstance(value, dict):
            if value.get("type") == resource_type and "attributes" in value:
                found[value["id"]] = value
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(payload)
    return list(found.values())


def renamed(value):
    def replace(match):
        old = match.group()
        return "setzo" if old.islower() else "SETZO" if old.isupper() else "Setzo"

    return re.sub("ironlog", replace, value, flags=re.IGNORECASE)


def changed_fields(attributes, fields):
    flags = []
    for field, flag in fields.items():
        old = attributes.get(field)
        if isinstance(old, str) and renamed(old) != old:
            flags.extend([flag, renamed(old)])
    return flags


def main():
    registered_bundle_ids = resources(asc("bundle-ids", "list", "--paginate"), "bundleIds")
    bundle_ids = [item for item in registered_bundle_ids
                  if item["attributes"].get("identifier") == IOS_BUNDLE_ID]
    if len(bundle_ids) != 1:
        raise RuntimeError(f"Could not identify the existing iOS bundle ID among {len(registered_bundle_ids)} returned")
    bundle_id = bundle_ids[0]["id"]
    capabilities = resources(asc("bundle-ids", "capabilities", "list", "--bundle", bundle_id),
                             "bundleIdCapabilities")
    if not any(item["attributes"].get("capabilityType") == "APPLE_ID_AUTH" for item in capabilities):
        asc("bundle-ids", "capabilities", "add", "--bundle", bundle_id,
            "--capability", "APPLE_ID_AUTH", "--if-exists", "skip",
            "--settings", json.dumps([{"key": "APPLE_ID_AUTH_APP_CONSENT", "options": [
                {"key": "PRIMARY_APP_CONSENT", "enabled": True}
            ]}]))

    app = resources(asc("apps", "view", "--id", APP_ID), "apps")[0]
    primary_locale = app["attributes"]["primaryLocale"]
    asc("apps", "rename", "--app", APP_ID, "--locale", primary_locale, "--name", "Setzo")

    infos = resources(asc("localizations", "list", "--app", APP_ID,
                          "--type", "app-info", "--paginate"), "appInfoLocalizations")
    if not infos:
        raise RuntimeError("No app info localizations returned after renaming")
    for info in infos:
        flags = changed_fields(info["attributes"], {
            "subtitle": "--subtitle", "privacyPolicyText": "--privacy-policy-text",
            "privacyChoicesUrl": "--privacy-choices-url",
        })
        asc("localizations", "update", "--type", "app-info", "--id", info["id"],
            "--name", "Setzo", "--privacy-policy-url", PRIVACY_URL, *flags)

    versions = resources(asc("localizations", "list", "--app", APP_ID,
                             "--platform", "IOS", "--paginate"), "appStoreVersionLocalizations")
    for version in versions:
        flags = changed_fields(version["attributes"], {
            "description": "--description", "keywords": "--keywords",
            "promotionalText": "--promotional-text", "whatsNew": "--whats-new",
        })
        asc("localizations", "update", "--id", version["id"],
            "--marketing-url", WEBSITE_URL, "--support-url", SUPPORT_URL, *flags)

    # IronFuel and workout guidance are health/wellness topics in Apple's age
    # questionnaire. Preserve the other age-rating answers for human review.
    asc("age-rating", "edit", "--app", APP_ID, "--health-or-wellness-topics", "true")

    for version in resources(asc("versions", "list", "--app", APP_ID, "--paginate"), "appStoreVersions"):
        if version["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION":
            asc("review", "details-create", "--version-id", version["id"],
                "--contact-first-name", "Neeraj", "--contact-last-name", "Chormale",
                "--contact-email", SUPPORT_EMAIL, "--if-exists", "update")

    betas = resources(asc("testflight", "app-localizations", "list", "--app", APP_ID,
                          "--paginate"), "betaAppLocalizations")
    for beta in betas:
        flags = changed_fields(beta["attributes"], {
            "description": "--description",
            "tvOsPrivacyPolicy": "--tv-os-privacy-policy",
        })
        asc("testflight", "app-localizations", "update", "--id", beta["id"],
            "--privacy-policy-url", PRIVACY_URL, "--marketing-url", WEBSITE_URL, *flags)

    groups = resources(asc("testflight", "groups", "list", "--app", APP_ID,
                           "--paginate"), "betaGroups")
    for group in groups:
        old = group["attributes"]["name"]
        if renamed(old) != old:
            asc("testflight", "groups", "edit", "--id", group["id"], "--name", renamed(old))

    # Apple identifiers remain stable; their editable display names can change.
    for identifier, name in [
        ("com.parthjadhav.ironlog", "Setzo"),
        ("com.parthjadhav.ironlog.IronLogWidget", "Setzo Widget"),
    ]:
        bundles = [item for item in resources(asc("bundle-ids", "list", "--paginate"), "bundleIds")
                   if item["attributes"].get("identifier") == identifier]
        for bundle in bundles:
            if bundle["attributes"]["name"] != name:
                asc("bundle-ids", "update", "--id", bundle["id"], "--name", name)

    verified = resources(asc("localizations", "list", "--app", APP_ID,
                             "--type", "app-info", "--paginate"), "appInfoLocalizations")
    assert verified and all(v["attributes"]["name"] == "Setzo" for v in verified)
    assert all(v["attributes"]["privacyPolicyUrl"] == PRIVACY_URL for v in verified)
    print(json.dumps({"appId": APP_ID, "name": "Setzo", "privacyPolicyUrl": PRIVACY_URL,
                      "locales": [v["attributes"]["locale"] for v in verified]}))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        # asc diagnostics contain the Apple API error; credentials stay in its auth store.
        raise SystemExit(error.stderr.strip() or str(error)) from error
