#!/usr/bin/env python3
"""
Find unused localization strings.
"""

import argparse
import sys
import os
import re
import pathlib
from typing import Iterable


project_root = pathlib.Path(__file__).parent.parent.resolve()
key_re = re.compile('^"([^"]+)" =')


def project_path(from_root: str) -> pathlib.Path:
    return project_root / from_root


def parse_args():
    parser = argparse.ArgumentParser(description="Find unused localization strings.")
    parser.add_argument(
        "--strings",
        type=pathlib.Path,
        default=project_path("Signal/translations/en.lproj/Localizable.strings"),
        help="A Localizable.strings file",
    )
    parser.add_argument(
        "--src_dirs",
        default=map(
            project_path,
            [
                "Signal/src",
                "SignalMessaging",
                "SignalNSE",
                "SignalServiceKit",
                "SignalShareExtension",
                "SignalUI",
            ],
        ),
        nargs="+",
        type=pathlib.Path,
        help="One or more source directories",
    )
    return parser.parse_args()


def get_all_keys(strings_file: pathlib.Path) -> Iterable[str]:
    with open(strings_file, "r") as file:
        for line in file:
            match = key_re.match(line)
            if match:
                yield match.group(1)


def get_all_file_paths(src_dir: os.PathLike) -> Iterable[str]:
    for root, _, files in os.walk(src_dir):
        for name in files:
            yield os.path.join(root, name)


def matching_substrings(file_path: str, substrings: Iterable[bytes]) -> Iterable[bytes]:
    with open(file_path, "rb") as file:
        contents = file.read()
    return filter(lambda s: s in contents, substrings)


def get_unused_keys(
    strings_file: pathlib.Path, src_dirs: Iterable[pathlib.Path]
) -> Iterable[str]:
    all_keys = get_all_keys(strings_file)
    all_keys_as_bytes = [key.encode() for key in all_keys]

    keys_not_seen = set(all_keys_as_bytes)

    for src_dir in src_dirs:
        for file_path in get_all_file_paths(src_dir):
            keys_seen = matching_substrings(file_path, keys_not_seen)
            keys_not_seen -= set(keys_seen)

    return map(lambda k: k.decode(), keys_not_seen)


def main() -> None:
    args = parse_args()

    unused_keys = get_unused_keys(args.strings, args.src_dirs)
    sorted_unused_keys = sorted(unused_keys)

    for key in sorted_unused_keys:
        print(key)

    if len(sorted_unused_keys) != 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
