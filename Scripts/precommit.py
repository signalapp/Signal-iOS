#!/usr/bin/env python3

import os
import sys
import subprocess
import argparse
from typing import Iterable
from pathlib import Path
from lint.util import EXTENSIONS_TO_CHECK


git_repo_path = os.path.abspath(
    subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
)


def sort_forward_decl_statement_block(text, filepath, filename, file_extension):
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
        if prev_line.strip():
            break
        first_matching_line_index = first_matching_line_index - 1

    first_non_matching_line_index = None
    for index, line in enumerate(lines[first_matching_line_index:]):
        if not line.strip():
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


def sort_matching_blocks(
    sort_name, filepath, filename, file_extension, text, match_func, sort_func
):
    unprocessed = text
    processed = None
    while True:
        section = find_matching_section(unprocessed, match_func)
        # print '\t', 'sort_matching_blocks', section
        if not section:
            if processed:
                processed = "\n".join(
                    (
                        processed,
                        unprocessed,
                    )
                )
            else:
                processed = unprocessed
            break

        text0, text1, text2 = section

        if processed:
            processed = "\n".join(
                (
                    processed,
                    text0,
                )
            )
        else:
            processed = text0

        # print 'before:'
        # temp_lines = text1.split('\n')
        # for index, line in enumerate(temp_lines):
        #     if index < 3 or index + 3 >= len(temp_lines):
        #         print '\t', index, line
        # # print text1
        # print
        text1 = sort_func(text1, filepath, filename, file_extension)
        # print 'after:'
        # # print text1
        # temp_lines = text1.split('\n')
        # for index, line in enumerate(temp_lines):
        #     if index < 3 or index + 3 >= len(temp_lines):
        #         print '\t', index, line
        # print
        processed = "\n".join(
            (
                processed,
                text1,
            )
        )
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


def sort_forward_class_statements(filepath, filename, file_extension, text):
    # print 'sort_class_statements', filepath
    if file_extension not in (".h", ".m", ".mm"):
        return text
    return sort_matching_blocks(
        "sort_class_statements",
        filepath,
        filename,
        file_extension,
        text,
        find_forward_class_statement_section,
        sort_forward_decl_statement_block,
    )


def sort_forward_protocol_statements(filepath, filename, file_extension, text):
    # print 'sort_class_statements', filepath
    if file_extension not in (".h", ".m", ".mm"):
        return text
    return sort_matching_blocks(
        "sort_forward_protocol_statements",
        filepath,
        filename,
        file_extension,
        text,
        find_forward_protocol_statement_section,
        sort_forward_decl_statement_block,
    )


def get_ext(file: str) -> str:
    return os.path.splitext(file)[1]


def process(filepath):
    short_filepath = filepath[len(git_repo_path) :]
    if short_filepath.startswith(os.sep):
        short_filepath = short_filepath[len(os.sep) :]

    filename = os.path.basename(filepath)
    if filename.startswith("."):
        raise Exception("shouldn't call process with dotfile")
    file_ext = get_ext(filename)

    with open(filepath, "rt") as f:
        text = f.read()

    original_text = text

    text = sort_forward_class_statements(filepath, filename, file_ext, text)
    text = sort_forward_protocol_statements(filepath, filename, file_ext, text)
    text = text.strip() + "\n"

    if original_text == text:
        return

    print("Updating:", short_filepath)

    with open(filepath, "wt") as f:
        f.write(text)


def get_file_paths_in(path: str) -> Iterable[str]:
    for rootdir, _, filenames in os.walk(path):
        for filename in filenames:
            yield os.path.abspath(os.path.join(rootdir, filename))


def get_file_paths_for_commands(commands: Iterable[list[str]]) -> Iterable[str]:
    for command in commands:
        lines = subprocess.check_output(command, text=True).split("\n")
        for line in lines:
            file_path = os.path.abspath(os.path.join(git_repo_path, line))
            if os.path.exists(file_path):
                yield file_path


def should_process_file(file_path: str) -> bool:
    if get_ext(file_path) not in EXTENSIONS_TO_CHECK:
        return False

    for component in Path(file_path).parts:
        if component.startswith("."):
            return False
        if component.endswith(".framework"):
            return False
        if component in (
            "Pods",
            "ThirdParty",
            "Carthage",
        ):
            return False

    return True


def lint_swift_files(file_paths: set[str]) -> bool:
    swift_file_paths = list(filter(lambda f: get_ext(f) == ".swift", file_paths))

    file_count = len(swift_file_paths)
    if file_count < 1:
        return True

    env = os.environ.copy()
    env["SCRIPT_INPUT_FILE_COUNT"] = str(file_count)
    for i, file_path in enumerate(swift_file_paths):
        env[f"SCRIPT_INPUT_FILE_{i}"] = file_path

    subprocess.run(
        ["swiftlint", "lint", "--fix", "--use-script-input-files"],
        env=env,
    )

    proc = subprocess.run(
        ["swiftlint", "lint", "--strict", "--use-script-input-files"],
        env=env,
    )

    return proc.returncode == 0


def check_diff_for_keywords():
    objc_keywords = [
        "OWSAbstractMethod\(",
        "OWSAssert\(",
        "OWSCAssert\(",
        "OWSFail\(",
        "OWSCFail\(",
        "ows_add_overflow\(",
        "ows_sub_overflow\(",
    ]

    swift_keywords = [
        "owsFail\(",
        "precondition\(",
        "fatalError\(",
        "dispatchPrecondition\(",
        "preconditionFailure\(",
        "notImplemented\(",
    ]

    keywords = objc_keywords + swift_keywords

    matching_expression = "|".join(keywords)
    command_line = (
        'git diff --staged | grep --color=always -C 3 -E "%s"' % matching_expression
    )
    try:
        output = subprocess.check_output(command_line, shell=True, text=True)
    except subprocess.CalledProcessError as e:
        # > man grep
        #  EXIT STATUS
        #  The grep utility exits with one of the following values:
        #  0     One or more lines were selected.
        #  1     No lines were selected.
        #  >1    An error occurred.
        if e.returncode == 1:
            # no keywords in diff output
            return
        else:
            # some other error - bad grep expression?
            raise e

    if len(output) > 0:
        print("⚠️  keywords detected in diff:")
        print(output)


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="Precommit script.")
    parser.add_argument(
        "--all", action="store_true", help="process all files in or below current dir"
    )
    parser.add_argument("--path", help="used to specify a path to process.")
    parser.add_argument(
        "--ref", help="process all files that have changed since the given ref"
    )
    parser.add_argument(
        "--skip_license_header_checks",
        action="store_true",
        help="A temporary flag that will skip license header checks. We plan to remove this flag soon.",
    )
    args = parser.parse_args()

    all_file_paths: Iterable[str] = []
    clang_format_commit = "HEAD"
    if args.all:
        all_file_paths = get_file_paths_in(git_repo_path)
    elif args.path:
        all_file_paths = get_file_paths_in(args.path)
    elif args.ref:
        all_file_paths = get_file_paths_for_commands(
            [["git", "diff", "--name-only", "--diff-filter=ACMR", args.ref, "HEAD"]]
        )
        clang_format_commit = args.ref
    else:
        all_file_paths = get_file_paths_for_commands(
            [
                ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
                ["git", "diff", "--name-only", "--diff-filter=ACMR"],
            ]
        )

    file_paths = set(filter(should_process_file, all_file_paths))

    result = True

    if not args.skip_license_header_checks:
        proc = subprocess.run(["Scripts/lint/lint-license-headers", "--fix"])
        if proc.returncode != 0:
            result = False

    print("Running SwiftLint...", flush=True)
    if not lint_swift_files(file_paths):
        result = False
    print("")

    print("Sorting forward declarations...", flush=True)
    for file_path in file_paths:
        process(file_path)
    print("")

    print("Sorting Xcode project...", flush=True)
    subprocess.run(["Scripts/sort-Xcode-project-file", "Signal.xcodeproj"])
    print("")

    print("Running clang-format...", flush=True)
    # we don't want to format .proto files, so we specify every other supported extension
    subprocess.run(
        [
            "git",
            "clang-format",
            "--extensions",
            "c,h,m,mm,cc,cp,cpp,c++,cxx,hh,hxx,cu,java,js,ts,cs",
            "--commit",
            clang_format_commit,
        ]
    )
    print("")

    print("Checking for keywords...", flush=True)
    check_diff_for_keywords()
    print("")

    if not result:
        print("Some errors couldn't be fixed automatically.")
        sys.exit(1)
