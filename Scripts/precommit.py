#!/usr/bin/env python3

import os
import sys
import subprocess
import datetime
import argparse
from typing import Iterable
from pathlib import Path


EXTENSIONS_TO_CHECK = set((
    ".h", ".hpp", ".cpp", ".m", ".mm", ".pch", ".swift"
))


git_repo_path = os.path.abspath(
    subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()
)



class include:
    def __init__(self, isInclude, isQuote, body, comment):
        self.isInclude = isInclude
        self.isQuote = isQuote
        self.body = body
        self.comment = comment

    def format(self):
        result = '%s %s%s%s' % (
                                ('#include' if self.isInclude else '#import'),
                                ('"' if self.isQuote else '<'),
                                self.body.strip(),
                                ('"' if self.isQuote else '>'),
                                )
        if self.comment.strip():
            result += ' ' + self.comment.strip()
        return result


def is_include_or_import(line):
    line = line.strip()
    if line.startswith('#include '):
        return True
    elif line.startswith('#import '):
        return True
    else:
        return False


def parse_include(line):
    remainder = line.strip()

    if remainder.startswith('#include '):
        isInclude = True
        remainder = remainder[len('#include '):]
    elif remainder.startswith('#import '):
        isInclude = False
        remainder = remainder[len('#import '):]
    elif remainder == '//':
        return None
    elif not remainder:
        return None
    else:
        print('Unexpected import or include: ' + line)
        sys.exit(1)

    comment = None
    if remainder.startswith('"'):
        isQuote = True
        endIndex = remainder.find('"', 1)
        if endIndex < 0:
            print('Unexpected import or include: ' + line)
            sys.exit(1)
        body = remainder[1:endIndex]
        comment = remainder[endIndex+1:]
    elif remainder.startswith('<'):
        isQuote = False
        endIndex = remainder.find('>', 1)
        if endIndex < 0:
            print('Unexpected import or include: ' + line)
            sys.exit(1)
        body = remainder[1:endIndex]
        comment = remainder[endIndex+1:]
    else:
        print('Unexpected import or include: ' + remainder)
        sys.exit(1)

    return include(isInclude, isQuote, body, comment)


def parse_includes(text):
    lines = text.split('\n')

    includes = []
    for line in lines:
        include = parse_include(line)
        if include:
            includes.append(include)

    return includes


def sort_include_block(text, filepath, filename, file_extension):
    includes = parse_includes(text)

    blocks = []

    file_extension = file_extension.lower()

    for include in includes:
        include.isInclude = False

    if file_extension in ('c', 'cpp', 'hpp'):
        for include in includes:
            include.isInclude = True
    elif file_extension in ('m'):
        for include in includes:
            include.isInclude = False

    # Make sure matching header is first.
    matching_header_includes = []
    other_includes = []
    def is_matching_header(include):
        filename_wo_ext = os.path.splitext(filename)[0]
        include_filename_wo_ext = os.path.splitext(os.path.basename(include.body))[0]
        return filename_wo_ext == include_filename_wo_ext
    for include in includes:
        if is_matching_header(include):
            matching_header_includes.append(include)
        else:
            other_includes.append(include)
    includes = other_includes

    def formatBlock(includes):
        lines = set([include.format() for include in includes])
        return "\n".join(sorted(lines))

    includeAngles = [include for include in includes if include.isInclude and not include.isQuote]
    includeQuotes = [include for include in includes if include.isInclude and include.isQuote]
    importAngles = [include for include in includes if (not include.isInclude) and not include.isQuote]
    importQuotes = [include for include in includes if (not include.isInclude) and include.isQuote]
    if matching_header_includes:
        blocks.append(formatBlock(matching_header_includes))
    if includeQuotes:
        blocks.append(formatBlock(includeQuotes))
    if includeAngles:
        blocks.append(formatBlock(includeAngles))
    if importQuotes:
        blocks.append(formatBlock(importQuotes))
    if importAngles:
        blocks.append(formatBlock(importAngles))

    return '\n'.join(blocks) + '\n'


def sort_forward_decl_statement_block(text, filepath, filename, file_extension):
    lines = text.split('\n')
    lines = [line.strip() for line in lines if line.strip()]
    lines = list(set(lines))
    lines.sort()
    return '\n' + '\n'.join(lines) + '\n'


def find_matching_section(text, match_test):
    lines = text.split('\n')
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

    text0 = '\n'.join(lines[:first_matching_line_index])
    if first_non_matching_line_index is None:
        text1 = '\n'.join(lines[first_matching_line_index:])
        text2 = None
    else:
        text1 = '\n'.join(lines[first_matching_line_index:first_non_matching_line_index])
        text2 = '\n'.join(lines[first_non_matching_line_index:])

    return text0, text1, text2


def sort_matching_blocks(sort_name, filepath, filename, file_extension, text, match_func, sort_func):
    unprocessed = text
    processed = None
    while True:
        section = find_matching_section(unprocessed, match_func)
        # print '\t', 'sort_matching_blocks', section
        if not section:
            if processed:
                processed = '\n'.join((processed, unprocessed,))
            else:
                processed = unprocessed
            break

        text0, text1, text2 = section

        if processed:
            processed = '\n'.join((processed, text0,))
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
        processed = '\n'.join((processed, text1,))
        if text2:
            unprocessed = text2
        else:
            break

    if text != processed:
        print(sort_name, filepath)
    return processed


def find_forward_class_statement_section(text):
    def is_forward_class_statement(line):
        return line.strip().startswith('@class ')

    return find_matching_section(text, is_forward_class_statement)


def find_forward_protocol_statement_section(text):
    def is_forward_protocol_statement(line):
        return line.strip().startswith('@protocol ') and line.strip().endswith(';') 

    return find_matching_section(text, is_forward_protocol_statement)


def find_include_section(text):
    def is_include_line(line):
        return is_include_or_import(line)
        # return is_include_or_import_or_empty(line)

    return find_matching_section(text, is_include_line)


def sort_includes(filepath, filename, file_extension, text):
    # print 'sort_includes', filepath
    if file_extension not in ('.h', '.m', '.mm'):
        return text
    return sort_matching_blocks('sort_includes', filepath, filename, file_extension, text, find_include_section, sort_include_block)


def sort_forward_class_statements(filepath, filename, file_extension, text):
    # print 'sort_class_statements', filepath
    if file_extension not in ('.h', '.m', '.mm'):
        return text
    return sort_matching_blocks('sort_class_statements', filepath, filename, file_extension, text, find_forward_class_statement_section, sort_forward_decl_statement_block)


def sort_forward_protocol_statements(filepath, filename, file_extension, text):
    # print 'sort_class_statements', filepath
    if file_extension not in ('.h', '.m', '.mm'):
        return text
    return sort_matching_blocks('sort_forward_protocol_statements', filepath, filename, file_extension, text, find_forward_protocol_statement_section, sort_forward_decl_statement_block)


def get_ext(file: str) -> str:
    return os.path.splitext(file)[1]


def process(filepath):
    short_filepath = filepath[len(git_repo_path):]
    if short_filepath.startswith(os.sep):
       short_filepath = short_filepath[len(os.sep):]

    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        raise Exception("shouldn't call process with dotfile")
    file_ext = get_ext(filename)

    with open(filepath, 'rt') as f:
        text = f.read()

    original_text = text

    text = sort_includes(filepath, filename, file_ext, text)
    text = sort_forward_class_statements(filepath, filename, file_ext, text)
    text = sort_forward_protocol_statements(filepath, filename, file_ext, text)

    lines = text.split('\n')

    shebang = ""
    if lines[0].startswith('#!'):
        shebang = lines[0] + '\n'
        lines = lines[1:]

    while lines and lines[0].startswith('//'):
        lines = lines[1:]
    text = '\n'.join(lines)
    text = text.strip()

    header = '''//
//  Copyright (c) %s Open Whisper Systems. All rights reserved.
//

''' % (
    datetime.datetime.now().year,
    )
    text = shebang + header + text + '\n'

    if original_text == text:
        return

    print('Updating:', short_filepath)

    with open(filepath, 'wt') as f:
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
        if component.startswith('.'):
            return False
        if component.endswith('.framework'):
            return False
        if component in ('Pods', 'ThirdParty', 'Carthage',):
            return False

    return True


def lint_swift_files(file_paths: set[str]) -> None:
    swift_file_paths = list(filter(
        lambda f: get_ext(f) == ".swift",
        file_paths
    ))

    file_count = len(swift_file_paths)
    if file_count < 1:
        return

    env = os.environ.copy()
    env["SCRIPT_INPUT_FILE_COUNT"] = str(file_count)
    for i, file_path in enumerate(swift_file_paths):
        env[f"SCRIPT_INPUT_FILE_{i}"] = file_path

    try:
        lint_output = subprocess.check_output(
            ["swiftlint", "lint", "--fix", "--use-script-input-files"],
            env=env,
            text=True
        )
    except subprocess.CalledProcessError as error:
        lint_output = error.output
    print(lint_output)

    try:
        lint_output = subprocess.check_output(
            ["swiftlint", "lint", "--use-script-input-files"],
            env=env,
            text=True
        )
    except subprocess.CalledProcessError as error:
        lint_output = error.output
    print(lint_output)


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
        "notImplemented\("
    ]

    keywords = objc_keywords + swift_keywords

    matching_expression = "|".join(keywords)
    command_line = 'git diff --staged | grep --color=always -C 3 -E "%s"' % matching_expression
    try:
        output = subprocess.check_output(command_line, shell=True)
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

    parser = argparse.ArgumentParser(description='Precommit script.')
    parser.add_argument('--all', action='store_true', help='process all files in or below current dir')
    parser.add_argument('--path', help='used to specify a path to process.')
    parser.add_argument('--ref', help='process all files that have changed since the given ref')
    args = parser.parse_args()

    all_file_paths: Iterable[str] = []
    clang_format_commit = 'HEAD'
    if args.all:
        all_file_paths = get_file_paths_in(git_repo_path)
    elif args.path:
        all_file_paths = get_file_paths_in(args.path)
    elif args.ref:
        all_file_paths = get_file_paths_for_commands([
            ["git", "diff", "--name-only", "--diff-filter=ACMR", args.ref, "HEAD"]
        ])
        clang_format_commit = args.ref
    else:
        all_file_paths = get_file_paths_for_commands([
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
            ["git", "diff", "--name-only", "--diff-filter=ACMR"]
        ])

    file_paths = set(filter(should_process_file, all_file_paths))

    lint_swift_files(file_paths)

    for file_path in file_paths:
        process(file_path)

    print('git clang-format...')
    # we don't want to format .proto files, so we specify every other supported extension
    print(subprocess.getoutput('git clang-format --extensions "c,h,m,mm,cc,cp,cpp,c++,cxx,hh,hxx,cu,java,js,ts,cs" --commit %s' % clang_format_commit))
 
    check_diff_for_keywords()
