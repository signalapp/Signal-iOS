#!/usr/bin/env python3

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "Signal/Settings.bundle/Acknowledgements.plist"
PODS_PATH = REPO_ROOT / "Pods"
THIRD_PARTY_PATH = REPO_ROOT / "ThirdParty"

POD_TARGETS = [
    "Signal",
    "SignalNSE",
    "SignalServiceKit",
    "SignalServiceKitTests",
    "SignalShareExtension",
    "SignalTests",
    "SignalUI",
    "SignalUITests",
]


def get_pod_acknowledgements_paths():
    paths = [
        PODS_PATH
        / "Target Support Files"
        / f"Pods-{target}"
        / f"Pods-{target}-acknowledgements.plist"
        for target in POD_TARGETS
    ]
    paths += [
        PODS_PATH / "LibSignalClient/acknowledgments/acknowledgments-ios.plist",
        PODS_PATH / "SignalRingRTC/acknowledgments/acknowledgments.plist",
        PODS_PATH / "SignalRingRTC/out/release/acknowledgments-webrtc-ios.plist",
    ]
    return paths


def get_specifier_groups(paths):
    groups = []
    for path in paths:
        output = subprocess.run(
            ["plutil", "-extract", "PreferenceSpecifiers", "json", "-o", "-", path],
            capture_output=True,
            encoding="utf8",
            check=True,
        ).stdout
        groups.append(json.loads(output))
    return groups


def get_third_party_specifiers():
    specifiers = []
    for manifest_path in sorted(THIRD_PARTY_PATH.glob("*/acknowledgement.json")):
        with open(manifest_path, "r", encoding="utf8") as file:
            manifest = json.load(file)
        license_path = manifest_path.parent / manifest["licenseFile"]
        specifiers.append(
            {
                "Type": "PSGroupSpecifier",
                "Title": manifest["title"],
                "FooterText": license_path.read_text(encoding="utf8"),
                "License": manifest["license"],
            }
        )
    return specifiers


def group_by_license(specifiers):
    titles_by_license = {}
    for specifier in specifiers:
        key = (specifier["FooterText"], specifier.get("License"))
        titles = titles_by_license.setdefault(key, {})
        for title in specifier["Title"].split(", "):
            titles[title] = None

    grouped_specifiers = []
    for (footer_text, license), titles in titles_by_license.items():
        grouped_specifier = {
            "Type": "PSGroupSpecifier",
            "Title": ", ".join(sorted(titles, key=str.lower)),
            "FooterText": footer_text,
        }
        if license is not None:
            grouped_specifier["License"] = license
        grouped_specifiers.append(grouped_specifier)

    return sorted(
        grouped_specifiers, key=lambda s: (s["Title"].lower(), s["FooterText"])
    )


def main():
    specifier_groups = get_specifier_groups(get_pod_acknowledgements_paths())

    header_specifier = specifier_groups[0][0]
    footer_specifier = specifier_groups[0][-1]

    specifiers = [s for group in specifier_groups for s in group[1:-1]]
    specifiers += get_third_party_specifiers()

    final_specifiers = (
        [header_specifier] + group_by_license(specifiers) + [footer_specifier]
    )

    subprocess.run(
        ["plutil", "-convert", "xml1", "-o", OUTPUT_PATH, "-"],
        input=json.dumps({"PreferenceSpecifiers": final_specifiers}),
        encoding="utf8",
        check=True,
    )


if __name__ == "__main__":
    main()
