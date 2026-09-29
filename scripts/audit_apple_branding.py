#!/usr/bin/env python3
"""Inspect every store locale and refresh the latest TestFlight rename notice."""
import json
from pathlib import Path
from sync_apple_branding import APP_ID, asc, resources, renamed

report = {"versions": [], "testflight": []}
for version in resources(asc("versions", "list", "--app", APP_ID, "--paginate"), "appStoreVersions"):
    entry = {"id": version["id"], "attributes": version["attributes"], "locales": []}
    for loc in resources(asc("localizations", "list", "--version", version["id"], "--paginate"), "appStoreVersionLocalizations"):
        entry["locales"].append({
            "id": loc["id"], "attributes": loc["attributes"],
            "screenshots": asc("screenshots", "list", "--version-localization", loc["id"]),
            "previews": asc("video-previews", "list", "--version-localization", loc["id"]),
        })
    report["versions"].append(entry)

notice = "IronLog is now Setzo. Update the existing app to keep your saved workouts and account. IronFuel keeps its name. Please check sign-in, workout history, and the new Setzo app icon."
builds = resources(asc("builds", "list", "--app", APP_ID, "--sort", "-uploadedDate", "--limit", "1"), "builds")
for build in builds:
    notes = resources(asc("builds", "test-notes", "list", "--build-id", build["id"]), "betaBuildLocalizations")
    for note in notes:
        old = note["attributes"].get("whatsNew") or ""
        updated = old if notice in old else renamed(old)
        if note["attributes"]["locale"].startswith("en") and notice not in old:
            updated = notice + ("\n\n" + updated if updated else "")
        if updated != old:
            asc("builds", "test-notes", "update", "--localization-id", note["id"], "--whats-new", updated)
    if not notes:
        asc("builds", "test-notes", "create", "--build-id", build["id"], "--locale", "en-US", "--whats-new", notice)
    report["testflight"].append(asc("builds", "test-notes", "list", "--build-id", build["id"]))

report["appInfo"] = asc("localizations", "list", "--app", APP_ID, "--type", "app-info", "--paginate")
report["betaApp"] = asc("testflight", "app-localizations", "list", "--app", APP_ID, "--paginate")
report["groups"] = asc("testflight", "groups", "list", "--app", APP_ID, "--paginate")
report["ageRating"] = asc("age-rating", "view", "--app", APP_ID)
bundle_ids = asc("bundle-ids", "list", "--identifier", "com.parthjadhav.ironlog")
report["iosBundleIDs"] = bundle_ids
for bundle in resources(bundle_ids, "bundleIds"):
    report["iosCapabilities"] = asc("bundle-ids", "capabilities", "list", "--bundle", bundle["id"])
report["reviewDetails"] = []
for version in report["versions"]:
    if version["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION":
        report["reviewDetails"].append(asc("review", "details-for-version", "--version-id", version["id"]))
Path("build").mkdir(exist_ok=True)
Path("build/apple-branding-audit.json").write_text(json.dumps(report, indent=2) + "\n")
print("Audited", len(report["versions"]), "store versions and refreshed latest TestFlight notes.")
