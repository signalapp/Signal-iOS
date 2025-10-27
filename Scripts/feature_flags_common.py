#!/usr/bin/env python3

import sys
import os
import re
import subprocess
import tag_template

FILE_PATH = "SignalServiceKit/Environment/BuildFlags+Generated.swift"


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

    changed_paths = []
    changed_paths.extend(tag_template.write_if_different(FILE_PATH, new_value))
    changed_paths.extend(tag_template.write_level(new_flags_level))
    changed_paths.extend(tag_template.write_template())

    if len(changed_paths) == 0:
        print(f"Feature flags already set to {new_flags_level}; nothing to do")
        exit(0)

    run(["git", "add", *changed_paths])
    run(["git", "commit", "-m", f"Feature flags for .{new_flags_level}."])
