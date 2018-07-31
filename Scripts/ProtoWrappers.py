#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import subprocess 
import datetime
import argparse
import commands
import re


git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())



# class include:
#     def __init__(self, isInclude, isQuote, body, comment):
#         self.isInclude = isInclude
#         self.isQuote = isQuote
#         self.body = body
#         self.comment = comment
#
#     def format(self):
#         result = '%s %s%s%s' % (
#                                 ('#include' if self.isInclude else '#import'),
#                                 ('"' if self.isQuote else '<'),
#                                 self.body.strip(),
#                                 ('"' if self.isQuote else '>'),
#                                 )
#         if self.comment.strip():
#             result += ' ' + self.comment.strip()
#         return result
#
#
# def is_include_or_import(line):
#     line = line.strip()
#     if line.startswith('#include '):
#         return True
#     elif line.startswith('#import '):
#         return True
#     else:
#         return False
#
#
# def parse_include(line):
#     remainder = line.strip()
#
#     if remainder.startswith('#include '):
#         isInclude = True
#         remainder = remainder[len('#include '):]
#     elif remainder.startswith('#import '):
#         isInclude = False
#         remainder = remainder[len('#import '):]
#     elif remainder == '//':
#         return None
#     elif not remainder:
#         return None
#     else:
#         print ('Unexpected import or include: '+ line)
#         sys.exit(1)
#
#     comment = None
#     if remainder.startswith('"'):
#         isQuote = True
#         endIndex = remainder.find('"', 1)
#         if endIndex < 0:
#             print ('Unexpected import or include: '+ line)
#             sys.exit(1)
#         body = remainder[1:endIndex]
#         comment = remainder[endIndex+1:]
#     elif remainder.startswith('<'):
#         isQuote = False
#         endIndex = remainder.find('>', 1)
#         if endIndex < 0:
#             print ('Unexpected import or include: '+ line)
#             sys.exit(1)
#         body = remainder[1:endIndex]
#         comment = remainder[endIndex+1:]
#     else:
#         print ('Unexpected import or include: '+ remainder)
#         sys.exit(1)
#
#     return include(isInclude, isQuote, body, comment)
#
#
# def parse_includes(text):
#     lines = text.split('\n')
#
#     includes = []
#     for line in lines:
#         include = parse_include(line)
#         if include:
#             includes.append(include)
#
#     return includes
#
#
# def sort_include_block(text, filepath, filename, file_extension):
#     lines = text.split('\n')
#
#     includes = parse_includes(text)
#
#     blocks = []
#
#     file_extension = file_extension.lower()
#
#     for include in includes:
#         include.isInclude = False
#
#     if file_extension in ('c', 'cpp', 'hpp'):
#         for include in includes:
#             include.isInclude = True
#     elif file_extension in ('m'):
#         for include in includes:
#             include.isInclude = False
#
#     # Make sure matching header is first.
#     matching_header_includes = []
#     other_includes = []
#     def is_matching_header(include):
#         filename_wo_ext = os.path.splitext(filename)[0]
#         include_filename_wo_ext = os.path.splitext(os.path.basename(include.body))[0]
#         return filename_wo_ext == include_filename_wo_ext
#     for include in includes:
#         if is_matching_header(include):
#             matching_header_includes.append(include)
#         else:
#             other_includes.append(include)
#     includes = other_includes
#
#     def formatBlock(includes):
#         lines = [include.format() for include in includes]
#         lines = list(set(lines))
#         def include_sorter(a, b):
#             # return cmp(a.lower(), b.lower())
#             return cmp(a, b)
#         # print 'before'
#         # for line in lines:
#         #     print '\t', line
#         # print
#         lines.sort(include_sorter)
#         # print 'after'
#         # for line in lines:
#         #     print '\t', line
#         # print
#         # print
#         # print 'filepath'
#         # for line in lines:
#         #     print '\t', line
#         # print
#         return '\n'.join(lines)
#
#     includeAngles = [include for include in includes if include.isInclude and not include.isQuote]
#     includeQuotes = [include for include in includes if include.isInclude and include.isQuote]
#     importAngles = [include for include in includes if (not include.isInclude) and not include.isQuote]
#     importQuotes = [include for include in includes if (not include.isInclude) and include.isQuote]
#     if matching_header_includes:
#         blocks.append(formatBlock(matching_header_includes))
#     if includeQuotes:
#         blocks.append(formatBlock(includeQuotes))
#     if includeAngles:
#         blocks.append(formatBlock(includeAngles))
#     if importQuotes:
#         blocks.append(formatBlock(importQuotes))
#     if importAngles:
#         blocks.append(formatBlock(importAngles))
#
#     return '\n'.join(blocks) + '\n'
#
#
# def sort_class_statement_block(text, filepath, filename, file_extension):
#     lines = text.split('\n')
#     lines = [line.strip() for line in lines if line.strip()]
#     lines = list(set(lines))
#     lines.sort()
#     return '\n' + '\n'.join(lines) + '\n'
#
#
# def find_matching_section(text, match_test):
#     lines = text.split('\n')
#     first_matching_line_index = None
#     for index, line in enumerate(lines):
#         if match_test(line):
#             first_matching_line_index = index
#             break
#
#     if first_matching_line_index is None:
#         return None
#
#     # Absorb any leading empty lines.
#     while first_matching_line_index > 0:
#         prev_line = lines[first_matching_line_index - 1]
#         if prev_line.strip():
#             break
#         first_matching_line_index = first_matching_line_index - 1
#
#     first_non_matching_line_index = None
#     for index, line in enumerate(lines[first_matching_line_index:]):
#         if not line.strip():
#             # Absorb any trailing empty lines.
#             continue
#         if not match_test(line):
#             first_non_matching_line_index = index + first_matching_line_index
#             break
#
#     text0 = '\n'.join(lines[:first_matching_line_index])
#     if first_non_matching_line_index is None:
#         text1 = '\n'.join(lines[first_matching_line_index:])
#         text2 = None
#     else:
#         text1 = '\n'.join(lines[first_matching_line_index:first_non_matching_line_index])
#         text2 = '\n'.join(lines[first_non_matching_line_index:])
#
#     return text0, text1, text2
#
#
# def sort_matching_blocks(sort_name, filepath, filename, file_extension, text, match_func, sort_func):
#     unprocessed = text
#     processed = None
#     while True:
#         section = find_matching_section(unprocessed, match_func)
#         # print '\t', 'sort_matching_blocks', section
#         if not section:
#             if processed:
#                 processed = '\n'.join((processed, unprocessed,))
#             else:
#                 processed = unprocessed
#             break
#
#         text0, text1, text2 = section
#
#         if processed:
#             processed = '\n'.join((processed, text0,))
#         else:
#             processed = text0
#
#         # print 'before:'
#         # temp_lines = text1.split('\n')
#         # for index, line in enumerate(temp_lines):
#         #     if index < 3 or index + 3 >= len(temp_lines):
#         #         print '\t', index, line
#         # # print text1
#         # print
#         text1 = sort_func(text1, filepath, filename, file_extension)
#         # print 'after:'
#         # # print text1
#         # temp_lines = text1.split('\n')
#         # for index, line in enumerate(temp_lines):
#         #     if index < 3 or index + 3 >= len(temp_lines):
#         #         print '\t', index, line
#         # print
#         processed = '\n'.join((processed, text1,))
#         if text2:
#             unprocessed = text2
#         else:
#             break
#
#     if text != processed:
#         print sort_name, filepath
#     return processed
#
#
# def find_class_statement_section(text):
#     def is_class_statement(line):
#         return line.strip().startswith('@class ')
#
#     return find_matching_section(text, is_class_statement)
#
#
# def find_include_section(text):
#     def is_include_line(line):
#         return is_include_or_import(line)
#         # return is_include_or_import_or_empty(line)
#
#     return find_matching_section(text, is_include_line)
#
#
# def sort_includes(filepath, filename, file_extension, text):
#     # print 'sort_includes', filepath
#     if file_extension not in ('.h', '.m', '.mm'):
#         return text
#     return sort_matching_blocks('sort_includes', filepath, filename, file_extension, text, find_include_section, sort_include_block)
#
#
# def sort_class_statements(filepath, filename, file_extension, text):
#     # print 'sort_class_statements', filepath
#     if file_extension not in ('.h', '.m', '.mm'):
#         return text
#     return sort_matching_blocks('sort_class_statements', filepath, filename, file_extension, text, find_class_statement_section, sort_class_statement_block)
#
#
# def splitall(path):
#     allparts = []
#     while 1:
#         parts = os.path.split(path)
#         if parts[0] == path:  # sentinel for absolute paths
#             allparts.insert(0, parts[0])
#             break
#         elif parts[1] == path: # sentinel for relative paths
#             allparts.insert(0, parts[1])
#             break
#         else:
#             path = parts[0]
#             allparts.insert(0, parts[1])
#     return allparts
#
#
# def process(filepath):
#
#     short_filepath = filepath[len(git_repo_path):]
#     if short_filepath.startswith(os.sep):
#        short_filepath = short_filepath[len(os.sep):]
#
#     filename = os.path.basename(filepath)
#     if filename.startswith('.'):
#         return
#     file_ext = os.path.splitext(filename)[1]
#     if file_ext in ('.swift'):
#         env_copy = os.environ.copy()
#         env_copy["SCRIPT_INPUT_FILE_COUNT"] = "1"
#         env_copy["SCRIPT_INPUT_FILE_0"] = '%s' % ( short_filepath, )
#         lint_output = subprocess.check_output(['swiftlint', 'autocorrect', '--use-script-input-files'], env=env_copy)
#         print lint_output
#         try:
#             lint_output = subprocess.check_output(['swiftlint', 'lint', '--use-script-input-files'], env=env_copy)
#         except subprocess.CalledProcessError, e:
#             lint_output = e.output
#         print lint_output
#
#     with open(filepath, 'rt') as f:
#         text = f.read()
#
#     original_text = text
#
#     text = sort_includes(filepath, filename, file_ext, text)
#     text = sort_class_statements(filepath, filename, file_ext, text)
#
#     lines = text.split('\n')
#     while lines and lines[0].startswith('//'):
#         lines = lines[1:]
#     text = '\n'.join(lines)
#     text = text.strip()
#
#     header = '''//
# //  Copyright (c) %s Open Whisper Systems. All rights reserved.
# //
#
# ''' % (
#     datetime.datetime.now().year,
#     )
#     text = header + text + '\n'
#
#     if original_text == text:
#         return
#
#     print 'Updating:', short_filepath
#
#     with open(filepath, 'wt') as f:
#         f.write(text)
#
#
# def should_ignore_path(path):
#     ignore_paths = [
#         os.path.join(git_repo_path, '.git')
#     ]
#     for ignore_path in ignore_paths:
#         if path.startswith(ignore_path):
#             return True
#     for component in splitall(path):
#         if component.startswith('.'):
#             return True
#         if component.endswith('.framework'):
#             return True
#         if component in ('Pods', 'ThirdParty', 'Carthage',):
#             return True
#
#     return False
#
#
# def process_if_appropriate(filepath):
#     filename = os.path.basename(filepath)
#     if filename.startswith('.'):
#         return
#     file_ext = os.path.splitext(filename)[1]
#     if file_ext not in ('.h', '.hpp', '.cpp', '.m', '.mm', '.pch', '.swift'):
#         return
#     if should_ignore_path(filepath):
#         return
#     process(filepath)

# class LineParser:
#     def __init__(self, lines):
#         self.lines = lines
#
#     def
    
# def process_proto_file(proto_file_path, dst_dir_path, is_verbose):



class FileContext:
    def __init__(self):


        self.messages = []
        self.enums = []
        
        self.package = None


class MessageContext:
    def __init__(self):
        self.name = None

        self.messages = []
        self.enums = []
        
        self.fields = []
        self.field_names = set()
        self.field_indices = set()
        
        
class EnumContext:
    def __init__(self):
        self.name = None
        
        self.item_names = set()
        self.item_indices = set()
        self.item_map = {}


def line_parser(text, is_verbose):
    # lineParser = LineParser(text.split('\n'))
    
    for line in text.split('\n'):
        line = line.strip()
        # if not line:
        #     continue

        comment_index = line.find('//')
        if comment_index >= 0:
            line = line[:comment_index].strip()
        if not line:
            continue
        
        if is_verbose:
            print 'line:', line
            
        yield line
        

def parse_enum(proto_file_path, parser, parent_context, enum_name, is_verbose):

    if is_verbose:
        print '# enum:', enum_name
    
    context = EnumContext()
    context.name = enum_name
    
    while True:
        try:
            line = parser.next()
        except StopIteration:
            raise Exception('Incomplete enum: %s' % proto_file_path)
    
        if line == '}':
            if is_verbose:
                print
            parent_context.enums.append(context)
            return

        item_regex = re.compile(r'^(.+?)\s*=\s*(\d+?)\s*;$')
        item_match = item_regex.search(line)
        if item_match:
            item_name = item_match.group(1).strip()
            item_index = item_match.group(2).strip()
        
            if is_verbose:
                print '\t enum item[%s]: %s' % (item_index, item_name)
            
            if item_name in context.item_names:
                raise Exception('Duplicate enum name[%s]: %s' % (proto_file_path, item_name))
            context.item_names.add(item_name)
            
            if item_index in context.item_indices:
                raise Exception('Duplicate enum index[%s]: %s' % (proto_file_path, item_name))
            context.item_indices.add(item_index)
            
            context.item_map[item_index] = item_name
                
            continue
    
        raise Exception('Invalid enum syntax[%s]: %s' % (proto_file_path, line))
        

def optional_match_group(match, index):
    group = match.group(index)
    if group is None:
        return None
    return group.strip()


def parse_message(proto_file_path, parser, parent_context, message_name, is_verbose):

    if is_verbose:
        print '# message:', message_name
    
    context = MessageContext()
    context.name = message_name
        
    while True:
        try:
            line = parser.next()
        except StopIteration:
            raise Exception('Incomplete message: %s' % proto_file_path)
    
        if line == '}':
            if is_verbose:
                print
            parent_context.messages.append(context)
            return

        enum_regex = re.compile(r'^enum\s+(.+?)\s+\{$')
        enum_match = enum_regex.search(line)
        if enum_match:
            enum_name = enum_match.group(1).strip()        
            parse_enum(proto_file_path, parser, context, enum_name, is_verbose)
            continue
        
        message_regex = re.compile(r'^message\s+(.+?)\s+\{$')
        message_match = message_regex.search(line)
        if message_match:
            message_name = message_match.group(1).strip()
            parse_message(proto_file_path, parser, context, message_name, is_verbose)
            continue

        # Examples:
        #
        # optional bytes  id          = 1;
        # optional bool              isComplete = 2 [default = false];
        item_regex = re.compile(r'^(optional|required|repeated)?\s*([\w\d]+?)\s+([\w\d]+?)\s*=\s*(\d+?)\s*(\[default = (true|false)\])?;$')
        item_match = item_regex.search(line)
        if item_match:
            # print 'item_rules:', item_match.groups()
            item_rules = optional_match_group(item_match, 1)
            item_type = optional_match_group(item_match, 2)
            item_name = optional_match_group(item_match, 3)
            item_index = optional_match_group(item_match, 4)
            # item_defaults_1 = optional_match_group(item_match, 5)
            item_default = optional_match_group(item_match, 6)
    
            # print 'item_rules:', item_rules
            # print 'item_type:', item_type
            # print 'item_name:', item_name
            # print 'item_index:', item_index
            # print 'item_default:', item_default
            
            message_field = {
                'rules': item_rules,
                'type': item_type,
                'name': item_name,
                'index': item_index,
                'default': item_default,
            }
            # print 'message_field:', message_field
        
            if is_verbose:
                print '\t message field[%s]: %s' % (item_index, str(message_field))
            
            if item_name in context.field_names:
                raise Exception('Duplicate message field name[%s]: %s' % (proto_file_path, item_name))
            context.field_names.add(item_name)
            
            if item_index in context.field_indices:
                raise Exception('Duplicate message field index[%s]: %s' % (proto_file_path, item_name))
            context.field_indices.add(item_index)
            
            context.fields.append(message_field)
            
            # if item_name in context.item_names:
            #     raise Exception('Duplicate message field[%s]: %s' % (proto_file_path, item_name))
            # context.item_names.add(item_name)
            #
            # if item_index in context.item_map:
            #     raise Exception('Duplicate message field[%s]: %s' % (proto_file_path, item_index))
            # context.item_map[item_index] = item_name
                
            continue

        raise Exception('Invalid message syntax[%s]: %s' % (proto_file_path, line))
    
    
def process_proto_file(proto_file_path, dst_dir_path, is_verbose):
    with open(proto_file_path, 'rt') as f:
        text = f.read()
    
    multiline_comment_regex = re.compile(r'/\*.*?\*/', re.MULTILINE|re.DOTALL)
    text = multiline_comment_regex.sub('', text)
    
    syntax_regex = re.compile(r'^syntax ')
    package_regex = re.compile(r'^package\s+(.+);')
    option_regex = re.compile(r'^option ')
    
    parser = line_parser(text, is_verbose)
    
    # lineParser = LineParser(text.split('\n'))
    
    context = FileContext()
    
    while True:
        try:
            line = parser.next()
        except StopIteration:
            break
        # if not line:
        #     break
    # for line in text.split('\n'):
    #     line = line.strip()
    #     if not line:
    #         continue

        # if is_verbose:
        #     print 'line:', line

        if syntax_regex.search(line):
            if is_verbose:
                print '# Ignoring syntax'
            continue
        
        if option_regex.search(line):
            if is_verbose:
                print '# Ignoring option'
            continue
        
        package_match = package_regex.search(line)
        if package_match:
            if context.package:
                raise Exception('More than one package statement: %s' % proto_file_path)
            context.package = package_match.group(1).strip()
            
            if is_verbose:
                print '# package:', context.package
            continue
        
        message_regex = re.compile(r'^message\s+(.+?)\s+\{$')
        message_match = message_regex.search(line)
        if message_match:
            message_name = message_match.group(1).strip()
            parse_message(proto_file_path, parser, context, message_name, is_verbose)
            continue
    
        raise Exception('Invalid syntax[%s]: %s' % (proto_file_path, line))
    
    
if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description='Protocol Buffer Swift Wrapper Generator.')
    # parser.add_argument('--all', action='store_true', help='process all files in or below current dir')
    # parser.add_argument('--path', help='used to specify a path to a file.')
    parser.add_argument('--proto-dir', help='dir path of the proto schema file.')
    parser.add_argument('--proto-file', help='filename of the proto schema file.')
    parser.add_argument('--wrapper-prefix', help='name prefix for generated wrappers.')
    parser.add_argument('--proto-prefix', help='name prefix for proto bufs.')
    parser.add_argument('--dst-dir', help='path to the destination directory.')
    parser.add_argument('--verbose', action='store_true', help='enables verbose logging')
    args = parser.parse_args()
    
    proto_file_path = os.path.abspath(os.path.join(args.proto_dir, args.proto_file))
    if not os.path.exists(proto_file_path):
        raise Exception('File does not exist: %s' % proto_file_path)
    
    dst_dir_path = os.path.abspath(args.dst_dir)
    if not os.path.exists(dst_dir_path):
        raise Exception('Destination does not exist: %s' % dst_dir_path)
    
    is_verbose = args.verbose
    
    process_proto_file(proto_file_path, dst_dir_path, is_verbose)
    print 'complete.'
    
    # if args.all:
    #     for rootdir, dirnames, filenames in os.walk(git_repo_path):
    #         for filename in filenames:
    #             file_path = os.path.abspath(os.path.join(rootdir, filename))
    #             process_if_appropriate(file_path)
    # elif args.path:
    #     for rootdir, dirnames, filenames in os.walk(args.path):
    #         for filename in filenames:
    #             file_path = os.path.abspath(os.path.join(rootdir, filename))
    #             process_if_appropriate(file_path)
    # else:
    #     filepaths = []
    #
    #     # Staging
    #     output = commands.getoutput('git diff --cached --name-only --diff-filter=ACMR')
    #     filepaths.extend([line.strip() for line in output.split('\n')])
    #
    #     # Working
    #     output = commands.getoutput('git diff --name-only --diff-filter=ACMR')
    #     filepaths.extend([line.strip() for line in output.split('\n')])
    #
    #     # Only process each path once.
    #     filepaths = sorted(set(filepaths))
    #
    #     for filepath in filepaths:
    #         filepath = os.path.abspath(os.path.join(git_repo_path, filepath))
    #         process_if_appropriate(filepath)

    # print 'git clang-format...'
    # print commands.getoutput('git clang-format')
