#!/usr/bin/env python3

import argparse
import json
import os
import plistlib
import subprocess
import sys


EVENT_PREFIXES = {
    "started": "🔨",
    "failed": "💥",
    "finished": "🚀",
}

WORKFLOW_PREFIXES = [
    "Nightly",
    "Release",
]


def get_marketing_version():
    with open("../Signal/Signal-Info.plist", "rb") as file:
        contents = plistlib.load(file)
    return contents["CFBundleShortVersionString"]


def build_payload(src, dst, message):
    payload = {
        "number": src,
        "recipients": [dst],
        "message": message,
    }
    return json.dumps(payload)


def main(ns):
    env = os.environ
    endpoint = env.get("NOTIFY_ENDPOINT")
    if endpoint is None:
        print("Doing nothing because there's no endpoint.")
        exit(0)
    workflow = env.get("CI_WORKFLOW", "")
    if not any(workflow.startswith(prefix) for prefix in WORKFLOW_PREFIXES):
        print(f"Doing nothing because '{workflow}' isn't valid.")
        exit(0)

    authorization = env["NOTIFY_AUTHORIZATION"]
    source = env["NOTIFY_SOURCE"]
    destination = env["NOTIFY_DESTINATION"]

    build_number = env["CI_BUILD_NUMBER"]
    build_url = env["CI_BUILD_URL"]
    prefix = EVENT_PREFIXES[ns.event]
    ref = env["CI_GIT_REF"]
    trigger = env["CI_START_CONDITION"]
    version = get_marketing_version()

    message = (
        f"{prefix} Cloud build for {version} ({build_number}) {ns.event} "
        f"from {ref} (trigger: {trigger})\n\n{build_url}"
    )
    args = ["curl", "--silent"]
    args.extend(["-H", "Content-Type: application/json"])
    args.extend(["-H", f"Authorization: {authorization}"])
    args.extend(["-d", build_payload(source, destination, message)])
    args.extend([endpoint])
    subprocess.run(args)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("event", choices=sorted(EVENT_PREFIXES.keys()))
    ns = parser.parse_args()
    main(ns)
