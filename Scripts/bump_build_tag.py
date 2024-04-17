#!/usr/bin/env python3

import argparse
import plistlib
import subprocess

INFO_PLIST_PATHS = [
    "Signal/Signal-Info.plist",
    "SignalShareExtension/Info.plist",
    "SignalNSE/Info.plist",
]


def run(args):
    subprocess.run(args, check=True)


def capture(args):
    return subprocess.run(args, check=True, capture_output=True, encoding="utf8").stdout


class Version:
    def __init__(self, major, minor, patch):
        self.major = major
        self.minor = minor
        self.patch = patch

    def pretty(self):
        return self.pretty2() if self.patch == 0 else self.pretty3()

    def pretty3(self):
        return f"{self.major}.{self.minor}.{self.patch}"

    def pretty2(self):
        assert self.patch == 0
        return f"{self.major}.{self.minor}"


def parse_version(value):
    components = list(map(int, value.split(".")))
    assert len(components) in (2, 3)
    while len(components) < 3:
        components.append(0)
    return Version(components[0], components[1], components[2])


def set_version(path, version):
    with open(path, "rb") as file:
        contents = plistlib.load(file)
    contents["CFBundleShortVersionString"] = version.pretty()
    with open(path, "wb") as file:
        plistlib.dump(contents, file)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="bumps the marketing version")
    parser.add_argument(
        "--version",
        metavar="x.y.z",
        required=True,
        help="specify the new marketing version number",
    )
    parser.add_argument(
        "--nightly", action="store_true", help="specify that this is a nightly build"
    )

    ns = parser.parse_args()

    output = capture(["git", "status", "--porcelain"]).rstrip()
    if len(output) > 0:
        print(output)
        print("Repository has uncommitted changes.")
        exit(1)

    version = parse_version(ns.version)

    for path in INFO_PLIST_PATHS:
        set_version(path, version)

    run(["git", "add", *INFO_PLIST_PATHS])
    run(["git", "commit", "-m", f"Bump version to {version.pretty()}"])
    if version.patch == 0:
        run(["git", "tag", f"version-{version.pretty2()}"])
