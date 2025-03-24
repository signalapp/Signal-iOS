#!/usr/bin/env python3

import plistlib

TEMPLATE_PATH = "ci_scripts/tag_template.txt"
FEATURE_FLAG_LEVEL_PATH = "ci_scripts/feature_flag_level.txt"
INFO_PLIST = "Signal/Signal-Info.plist"


def write_level(level):
    return write_if_different(FEATURE_FLAG_LEVEL_PATH, level)


def write_template():
    (major, minor, patch) = get_current_marketing_version()
    tag_suffix = get_tag_suffix(get_current_feature_flag_level())
    tag_template = f"{major}.{minor}.{patch}.{{build_number}}{tag_suffix}"
    return write_if_different(TEMPLATE_PATH, tag_template)


def get_current_marketing_version():
    with open(INFO_PLIST, "rb") as file:
        return extract_marketing_version(plistlib.load(file))


def extract_marketing_version(contents):
    return parse_version(contents["CFBundleShortVersionString"])


def parse_version(value):
    components = list(map(int, value.split(".")))
    while len(components) < 3:
        components.append(0)
    major, minor, patch = tuple(components)
    return (major, minor, patch)


def get_current_feature_flag_level():
    with open(FEATURE_FLAG_LEVEL_PATH, "r") as file:
        return file.read()


def get_tag_suffix(level):
    if level == "production":
        return ""
    return f"-{level}"


def write_if_different(file_path, new_value):
    with open(file_path, "r") as file:
        old_value = file.read()
    if new_value != old_value:
        with open(file_path, "w") as file:
            file.write(new_value)
        return [file_path]
    return []
