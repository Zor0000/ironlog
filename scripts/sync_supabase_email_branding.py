#!/usr/bin/env python3
"""Apply only the source-controlled email branding fields, then verify them."""
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

root = Path(__file__).resolve().parents[1]
payload = json.loads((root / "supabase/email-branding.json").read_text())
assert all(k == "smtp_sender_name" or k.startswith("mailer_subjects_") or
           (k.startswith("mailer_templates_") and k.endswith("_content")) for k in payload)
url = "https://api.supabase.com/v1/projects/dvqevdydldxjqjrpkkjc/config/auth"
headers = {"Authorization": "Bearer " + os.environ["SUPABASE_ACCESS_TOKEN"],
           "Content-Type": "application/json"}
with urlopen(Request(url, headers=headers, data=json.dumps(payload).encode(), method="PATCH"), timeout=30):
    pass
with urlopen(Request(url, headers=headers), timeout=30) as response:
    actual = json.load(response)
assert all(actual.get(key) == value for key, value in payload.items()), "Email branding verification failed"
print(f"Verified {len(payload)} email branding fields; authentication and delivery settings were not changed.")
