#!/usr/bin/env python3

import sys
import os
import re
import subprocess

FILE_PATH = "SignalServiceKit/Util/FeatureFlags+Generated.swift"


def run(args):
    subprocess.run(args, check=True)


def capture(args):
    return subprocess.run(args, check=True, capture_output=True, encoding="utf8").stdout


def generate(level):
    return """//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension FeatureBuild {
#if DEBUG
    static let current: FeatureBuild = .dev
#else
    static let current: FeatureBuild = .{level}
#endif
}
""".replace(
        "{level}", str(level)
    )


def set_feature_flags(new_flags_level):
    output = capture(["git", "status", "--porcelain"]).rstrip()
    if len(output) > 0:
        print(output)
        print("Repository has uncommitted changes.")
        exit(1)

    new_value = generate(new_flags_level)
    with open(FILE_PATH, "r") as file:
        old_value = file.read()

    if new_value == old_value:
        print(f"Feature flags already set to {new_flags_level}; nothing to do")
        exit(0)

    with open(FILE_PATH, "w") as file:
        file.write(new_value)

    run(["git", "add", FILE_PATH])
    run(["git", "commit", "-m", f"Feature flags for .{new_flags_level}."])
