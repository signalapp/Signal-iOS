#!/usr/bin/env python3

import subprocess


def get_actual_version():
    return subprocess.run(
        ["xcodebuild", "-version"], check=True, capture_output=True, encoding="utf8"
    ).stdout.split("\n")[0]


def get_expected_version():
    with open(".xcode-version", "r") as file:
        return file.read().rstrip()


def main():
    actual_version = get_actual_version()
    expected_version = get_expected_version()
    if actual_version != expected_version:
        print(
            f"You’re using {actual_version} but you should be using {expected_version}."
        )
        exit(1)


if __name__ == "__main__":
    main()
