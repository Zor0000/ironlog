#!/usr/bin/env python3
"""Apply the approved listing and retain sanitized Apple receipts."""

import json
import os
import subprocess
from pathlib import Path
from check_app_store_review import main as audit, redact


listing = json.loads(Path("docs/app-store-listing.json").read_text())
operations = []


def run(label, *args):
    result = subprocess.run(["asc", *args, "--output", "json"],
                            capture_output=True, text=True, timeout=300)
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError:
        response = {"responseUnavailable": True}
    # These operations never read credentials. Preserve API error reasons, but
    # redact any sensitive fields returned alongside a version or review item.
    operations.append({"operation": label, "exitCode": result.returncode,
                       "response": redact(response),
                       "error": result.stderr.strip() if result.returncode else None})
    print(f"{label}: {'completed' if result.returncode == 0 else 'failed; see receipt'}")
    return result.returncode, response


def prepare():
    app = listing["appId"]
    run("version listing", "localizations", "update", "--id", listing["localizationId"],
        "--description", listing["description"], "--keywords", listing["keywords"])
    run("subtitle", "localizations", "update", "--type", "app-info", "--id",
        listing["appInfoLocalizationId"], "--subtitle", listing["subtitle"])
    run("category", "categories", "set", "--app", app, "--primary", listing["primaryCategory"])
    run("content rights", "apps", "content-rights", "edit", "--app", app,
        "--uses-third-party-content", str(listing["usesThirdPartyContent"]).lower())
    run("copyright", "versions", "update", "--version-id", listing["versionId"],
        "--copyright", listing["copyright"])
    run("select build", "versions", "attach-build", "--version-id", listing["versionId"],
        "--build-id", listing["buildId"])
    code, territories = run("supported territories", "pricing", "territories", "list", "--paginate")
    if code == 0:
        ids = [item["id"] for item in territories["data"]]
        if not ids:
            raise RuntimeError("Apple returned no territories")
        run("worldwide availability", "pricing", "availability", "create", "--app", app,
            "--territory", ",".join(ids), "--available", "true",
            "--available-in-new-territories", "true", "--if-exists", "update")
    run("free price", "pricing", "schedule", "create", "--app", app,
        "--free", "--base-territory", "US")
    run("verify price", "pricing", "current", "--app", app, "--all-territories")
    screenshots = Path("images/app-store/en-US/iphone65")
    if screenshots.is_dir():
        run("screenshots", "screenshots", "upload", "--version-localization",
            listing["localizationId"], "--path", str(screenshots),
            "--device-type", "IPHONE_65", "--skip-existing")


def submit():
    release_type = os.environ.get("REVIEW_RELEASE_TYPE")
    if release_type not in ("MANUAL", "AFTER_APPROVAL"):
        raise RuntimeError("Release choice requires Neeraj's confirmation")
    code, _ = run("release choice", "versions", "update", "--version-id", listing["versionId"],
                  "--release-type", release_type)
    if code:
        raise RuntimeError("Could not apply release choice")
    code, _ = run("submission gate", "validate", "--app", listing["appId"],
                  "--version", listing["version"], "--platform", "IOS", "--check-urls")
    if code:
        raise RuntimeError("Apple readiness validation has blocking issues")
    code, _ = run("public review submission", "review", "submit", "--app", listing["appId"],
                  "--version-id", listing["versionId"], "--build-id", listing["buildId"], "--confirm")
    run("review status", "review", "status", "--app", listing["appId"],
        "--version", listing["version"], "--platform", "IOS")
    if code:
        raise RuntimeError("Apple did not accept the submission; see receipt")


if __name__ == "__main__":
    try:
        operation = os.environ.get("REVIEW_OPERATION", "inspect")
        if operation == "prepare":
            prepare()
        elif operation == "submit":
            submit()
        elif operation != "inspect":
            raise RuntimeError("Unknown review operation")
    finally:
        Path("build").mkdir(exist_ok=True)
        Path("build/app-store-review-operations.json").write_text(json.dumps(operations, indent=2) + "\n")
        audit()
