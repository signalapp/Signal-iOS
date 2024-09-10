#!/usr/bin/env python3

import os
import sys
import subprocess
import argparse
from typing import Iterable
from pathlib import Path
from lint.util import EXTENSIONS_TO_CHECK

CLANG_FORMAT_EXTS = set([".m", ".mm", ".h"])


def sort_forward_decl_statement_block(text):
    lines = text.split("\n")
    lines = [line.strip() for line in lines if line.strip()]
    lines = list(set(lines))
    lines.sort()
    return "\n" + "\n".join(lines) + "\n"


def find_matching_section(text, match_test):
    lines = text.split("\n")
    first_matching_line_index = None
    for index, line in enumerate(lines):
        if match_test(line):
            first_matching_line_index = index
            break

    if first_matching_line_index is None:
        return None

    # Absorb any leading empty lines.
    while first_matching_line_index > 0:
        prev_line = lines[first_matching_line_index - 1]
        if prev_line.strip() != "":
            break
        first_matching_line_index = first_matching_line_index - 1

    first_non_matching_line_index = None
    for index, line in enumerate(lines[first_matching_line_index:]):
        if line.strip() == "":
            # Absorb any trailing empty lines.
            continue
        if not match_test(line):
            first_non_matching_line_index = index + first_matching_line_index
            break

    text0 = "\n".join(lines[:first_matching_line_index])
    if first_non_matching_line_index is None:
        text1 = "\n".join(lines[first_matching_line_index:])
        text2 = None
    else:
        text1 = "\n".join(
            lines[first_matching_line_index:first_non_matching_line_index]
        )
        text2 = "\n".join(lines[first_non_matching_line_index:])

    return text0, text1, text2


def sort_matching_blocks(sort_name, filepath, text, match_func, sort_func):
    unprocessed = text
    processed = None
    while True:
        section = find_matching_section(unprocessed, match_func)
        if not section:
            if processed:
                processed = "\n".join((processed, unprocessed))
            else:
                processed = unprocessed
            break

        text0, text1, text2 = section

        if processed:
            processed = "\n".join((processed, text0))
        else:
            processed = text0

        text1 = sort_func(text1)
        processed = "\n".join((processed, text1))
        if text2:
            unprocessed = text2
        else:
            break

    if text != processed:
        print(sort_name, filepath)
    return processed


def find_forward_class_statement_section(text):
    def is_forward_class_statement(line):
        return line.strip().startswith("@class ")

    return find_matching_section(text, is_forward_class_statement)


def find_forward_protocol_statement_section(text):
    def is_forward_protocol_statement(line):
        return line.strip().startswith("@protocol ") and line.strip().endswith(";")

    return find_matching_section(text, is_forward_protocol_statement)


def sort_forward_class_statements(filepath, file_extension, text):
    if file_extension not in (".h", ".m", ".mm"):
        return text
    return sort_matching_blocks(
        "sort_class_statements",
        filepath,
        text,
        find_forward_class_statement_section,
        sort_forward_decl_statement_block,
    )


def sort_forward_protocol_statements(filepath, file_extension, text):
    if file_extension not in (".h", ".m", ".mm"):
        return text
    return sort_matching_blocks(
        "sort_forward_protocol_statements",
        filepath,
        text,
        find_forward_protocol_statement_section,
        sort_forward_decl_statement_block,
    )


def get_ext(file: str) -> str:
    return os.path.splitext(file)[1]


def process(filepath):
    file_ext = get_ext(filepath)

    with open(filepath, "rt") as f:
        text = f.read()

    original_text = text

    text = sort_forward_class_statements(filepath, file_ext, text)
    text = sort_forward_protocol_statements(filepath, file_ext, text)
    text = text.strip() + "\n"

    if original_text == text:
        return

    with open(filepath, "wt") as f:
        f.write(text)


def get_file_paths_for_commit(commit):
    return (
        subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=ACMR", commit],
            check=True,
            capture_output=True,
            encoding="utf8",
        )
        .stdout.rstrip()
        .split("\n")
    )


def should_process_file(file_path: str) -> bool:
    if get_ext(file_path) not in EXTENSIONS_TO_CHECK:
        return False

    for component in Path(file_path).parts:
        if component.startswith("."):
            return False
        if component in ("Pods", "ThirdParty"):
            return False
        if component.startswith("MobileCoinExternal."):
            return False

    return True


def swiftlint(file_paths):
    file_paths = list(filter(lambda f: get_ext(f) == ".swift", file_paths))
    if len(file_paths) == 0:
        return True

    subprocess.run(["swiftlint", "lint", "--quiet", "--fix", *file_paths])
    proc = subprocess.run(["swiftlint", "lint", "--quiet", "--strict", *file_paths])

    return proc.returncode == 0


def clang_format(file_paths):
    file_paths = list(filter(lambda f: get_ext(f) in CLANG_FORMAT_EXTS, file_paths))
    if len(file_paths) == 0:
        return True
    proc = subprocess.run(["clang-format", "-i", *file_paths])
    return proc.returncode == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="lint & format files")
    parser.add_argument("path", nargs="*", help="a path to process")
    parser.add_argument(
        "--ref",
        metavar="commit-sha",
        help="process paths that have changed since this commit",
    )
    parser.add_argument(
        "--skip-xcode-sort",
        action='store_true',
        help="skip sorting the Xcode project",
    )
    ns = parser.parse_args()

    if len(ns.path) > 0:
        file_paths = ns.path
    else:
        file_paths = get_file_paths_for_commit(ns.ref or "HEAD")
    file_paths = sorted(set(filter(should_process_file, file_paths)))

    result = True

    print("Checking license headers...", flush=True)
    proc = subprocess.run(["Scripts/lint/lint-license-headers", "--fix", *file_paths])
    if proc.returncode != 0:
        result = False
    print("")

    print("Running swiftlint...", flush=True)
    if not swiftlint(file_paths):
        result = False
    print("")

    print("Sorting forward declarations...", flush=True)
    for file_path in file_paths:
        process(file_path)
    print("")

    if ns.skip_xcode_sort:
        print("Skipping Xcode project sort!", flush=True)
    else:
        print("Sorting Xcode project...", flush=True)
        proc = subprocess.run(["Scripts/sort-Xcode-project-file", "Signal.xcodeproj"])
        if proc.returncode != 0:
            result = False
    print("")

    print("Running clang-format...", flush=True)
    if not clang_format(file_paths):
        result = False
    print("")

    if not result:
        print("Some errors couldn't be fixed automatically.")
        sys.exit(1)
