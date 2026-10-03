#!/usr/bin/env python3
"""Select an iPhone explicitly supported by an available iOS runtime."""

import json
import re
import sys


def select_pair(inventory: dict) -> tuple[str, str]:
    runtimes = sorted(
        (runtime for runtime in inventory["runtimes"]
         if runtime.get("isAvailable") and runtime["name"].startswith("iOS ")),
        key=lambda runtime: tuple(int(part) for part in runtime["version"].split(".")),
        reverse=True,
    )
    for runtime in runtimes:
        phones = [device for device in runtime.get("supportedDeviceTypes", [])
                  if device["name"].startswith("iPhone ") and "Max" not in device["name"]]
        if phones:
            # Do not use catalog order: a newer installed device may require a
            # newer runtime. The runtime's own compatibility list is authoritative.
            phone = max(phones, key=lambda device: (
                tuple(int(part) for part in re.findall(r"\d+", device["name"])),
                device["name"].endswith("Pro"),
                device["identifier"],
            ))
            return runtime["identifier"], phone["identifier"]
    raise ValueError("No available iOS runtime has a supported non-Max iPhone device type")


if __name__ == "__main__":
    try:
        print(*select_pair(json.load(sys.stdin)))
    except (KeyError, ValueError) as error:
        sys.exit(f"Cannot create Setzo E2E simulator: {error}")
