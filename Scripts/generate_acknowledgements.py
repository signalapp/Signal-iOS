#!/usr/bin/env python3

import json
import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "Signal/Settings.bundle/Acknowledgements.plist"
THIRD_PARTY_PATH = REPO_ROOT / "ThirdParty"
WORKSPACE_PATH = REPO_ROOT / "Signal.xcworkspace"
PACKAGE_RESOLVED_PATH = WORKSPACE_PATH / "xcshareddata/swiftpm/Package.resolved"

LICENSE_FILE_PATTERN = re.compile(r"^(LICEN[CS]E|COPYING)(\.(md|txt))?$", re.IGNORECASE)

SWIFT_PACKAGE_LICENSE_PATHS = {
    "mobilecoin-swift": {
        "MobileCoin": "LICENSE",
        "LibMobileCoin": "Vendor/libmobilecoin/LICENSE",
    },
}

TEST_ONLY_SWIFT_PACKAGES = {
    "signal-message-backup-tests",
}

HEADER_SPECIFIER = {
    "Type": "PSGroupSpecifier",
    "Title": "Acknowledgements",
    "FooterText": "This application makes use of the following third party libraries:",
}


def get_acknowledgements_paths(source_packages_path, workspace_state):
    return [
        get_checkout_path(source_packages_path, workspace_state, "libsignal")
        / "acknowledgments/acknowledgments-ios.plist",
        get_checkout_path(source_packages_path, workspace_state, "ringrtc")
        / "acknowledgments/acknowledgments.plist",
        get_artifact_path(workspace_state, "ringrtc", "WebRTC")
        / "acknowledgments-webrtc-ios.plist",
    ]


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


def get_source_packages_path():
    output = subprocess.run(
        [
            "xcodebuild",
            "-workspace",
            WORKSPACE_PATH,
            "-scheme",
            "Signal",
            "-showBuildSettings",
            "-json",
            "-disableAutomaticPackageResolution",
        ],
        capture_output=True,
        encoding="utf8",
        check=True,
    ).stdout
    build_path = Path(json.loads(output)[0]["buildSettings"]["BUILD_DIR"])
    return build_path.parent.parent / "SourcePackages"


def get_workspace_state(source_packages_path):
    with open(source_packages_path / "workspace-state.json", "r", encoding="utf8") as file:
        return json.load(file)["object"]


def get_dependency(workspace_state, identity):
    for dependency in workspace_state["dependencies"]:
        if dependency["packageRef"]["identity"] == identity:
            return dependency
    raise Exception(f"No checkout for {identity}")


def get_checkout_path(source_packages_path, workspace_state, identity):
    dependency = get_dependency(workspace_state, identity)
    return source_packages_path / "checkouts" / dependency["subpath"]


def verify_checkouts(pins, workspace_state):
    for pin in pins:
        identity = pin["identity"]
        expected = pin["state"]["revision"]
        actual = get_dependency(workspace_state, identity)["state"]["checkoutState"]["revision"]
        if actual != expected:
            raise Exception(
                f"{identity} is checked out at {actual} but Package.resolved pins "
                f"{expected}; resolve packages in Xcode and try again"
            )


def get_artifact_path(workspace_state, identity, target_name):
    for artifact in workspace_state["artifacts"]:
        if (
            artifact["packageRef"]["identity"] == identity
            and artifact["targetName"] == target_name
        ):
            return Path(artifact["path"])
    raise Exception(f"No artifact for {identity} {target_name}")


def get_license_paths(directory):
    return [p for p in directory.iterdir() if LICENSE_FILE_PATTERN.match(p.name)]


def get_submodule_paths(checkout_path):
    gitmodules_path = checkout_path / ".gitmodules"
    if not gitmodules_path.exists():
        return []
    output = subprocess.run(
        ["git", "config", "--file", gitmodules_path, "--get-regexp", r"\.path$"],
        capture_output=True,
        encoding="utf8",
        check=True,
    ).stdout
    return [checkout_path / line.split(" ", 1)[1] for line in output.splitlines()]


def get_swift_package_license_text(checkout_path):
    license_paths = get_license_paths(checkout_path)
    if not license_paths:
        for submodule_path in get_submodule_paths(checkout_path):
            license_paths += get_license_paths(submodule_path)
    if len(license_paths) != 1:
        raise Exception(f"Expected one license in {checkout_path}: {license_paths}")
    return license_paths[0].read_text(encoding="utf8")


def get_swift_package_name(checkout_path):
    output = subprocess.run(
        ["swift", "package", "dump-package", "--package-path", checkout_path],
        capture_output=True,
        encoding="utf8",
        check=True,
    ).stdout
    return json.loads(output)["name"]


def get_swift_package_specifiers(source_packages_path, workspace_state, pins):
    specifiers = []
    for pin in pins:
        identity = pin["identity"]
        if pin["kind"] != "remoteSourceControl":
            raise Exception(f"Unsupported kind for {identity}: {pin['kind']}")
        if identity in TEST_ONLY_SWIFT_PACKAGES:
            continue

        checkout_path = get_checkout_path(source_packages_path, workspace_state, identity)
        license_paths = SWIFT_PACKAGE_LICENSE_PATHS.get(identity)
        if license_paths is None:
            specifiers.append(
                {
                    "Type": "PSGroupSpecifier",
                    "Title": get_swift_package_name(checkout_path),
                    "FooterText": get_swift_package_license_text(checkout_path),
                }
            )
            continue

        for title, license_path in license_paths.items():
            specifiers.append(
                {
                    "Type": "PSGroupSpecifier",
                    "Title": title,
                    "FooterText": (checkout_path / license_path).read_text(
                        encoding="utf8"
                    ),
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

    return grouped_specifiers


def main():
    source_packages_path = get_source_packages_path()
    workspace_state = get_workspace_state(source_packages_path)
    with open(PACKAGE_RESOLVED_PATH, "r", encoding="utf8") as file:
        pins = json.load(file)["pins"]
    verify_checkouts(pins, workspace_state)

    specifier_groups = get_specifier_groups(
        get_acknowledgements_paths(source_packages_path, workspace_state)
    )

    specifiers = [s for group in specifier_groups for s in group[1:-1]]
    specifiers += get_third_party_specifiers()
    specifiers = group_by_license(specifiers)
    specifiers += get_swift_package_specifiers(source_packages_path, workspace_state, pins)
    specifiers.sort(key=lambda s: (s["Title"].lower(), s["FooterText"]))

    final_specifiers = [HEADER_SPECIFIER] + specifiers

    subprocess.run(
        ["plutil", "-convert", "xml1", "-o", OUTPUT_PATH, "-"],
        input=json.dumps({"PreferenceSpecifiers": final_specifiers}),
        encoding="utf8",
        check=True,
    )


if __name__ == "__main__":
    main()
