#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import subprocess 
import datetime
import argparse
import commands


git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())


def splitall(path):
    allparts = []
    while 1:
        parts = os.path.split(path)
        if parts[0] == path:  # sentinel for absolute paths
            allparts.insert(0, parts[0])
            break
        elif parts[1] == path: # sentinel for relative paths
            allparts.insert(0, parts[1])
            break
        else:
            path = parts[0]
            allparts.insert(0, parts[1])
    return allparts
    
    
def process(filepath):

    short_filepath = filepath[len(git_repo_path):]
    if short_filepath.startswith(os.sep):
       short_filepath = short_filepath[len(os.sep):] 
    
    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        return
    file_ext = os.path.splitext(filename)[1]
    if file_ext in ('.swift'):
        env_copy = os.environ.copy()
        env_copy["SCRIPT_INPUT_FILE_COUNT"] = "1"
        env_copy["SCRIPT_INPUT_FILE_0"] = '%s' % ( short_filepath, )
        lint_output = subprocess.check_output(['swiftlint', 'autocorrect', '--use-script-input-files'], env=env_copy)
        print lint_output
        lint_output = subprocess.check_output(['swiftlint', 'lint', '--use-script-input-files'], env=env_copy)
        print lint_output
    
    with open(filepath, 'rt') as f:
        text = f.read()
    original_text = text
    
    lines = text.split('\n')
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
    text = header + text + '\n'

    if original_text == text:
        return
    
    print 'Updating:', short_filepath
    
    with open(filepath, 'wt') as f:
        f.write(text)


def should_ignore_path(path):
    ignore_paths = [
        os.path.join(git_repo_path, '.git')
    ]
    for ignore_path in ignore_paths:
        if path.startswith(ignore_path):
            return True
    for component in splitall(path):
        if component.startswith('.'):
            return True
        if component.endswith('.framework'):
            return True
        if component in ('Pods', 'ThirdParty', 'Carthage',):
            return True                
        
    return False
    
    
def process_if_appropriate(filepath):
    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        return
    file_ext = os.path.splitext(filename)[1]
    if file_ext not in ('.h', '.hpp', '.cpp', '.m', '.mm', '.pch', '.swift'):
        return
    if should_ignore_path(filepath):
        return
    process(filepath)

    
if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description='Precommit script.')
    parser.add_argument('--all', action='store_true', help='process all files in or below current dir')
    args = parser.parse_args()
    
    if args.all:
        for rootdir, dirnames, filenames in os.walk(git_repo_path):
            for filename in filenames:
                file_path = os.path.abspath(os.path.join(rootdir, filename))
                process_if_appropriate(file_path)
    else:
        filepaths = []
        
        # Staging
        output = commands.getoutput('git diff --cached --name-only --diff-filter=ACMR')
        filepaths.extend([line.strip() for line in output.split('\n')])

        # Working
        output = commands.getoutput('git diff --name-only --diff-filter=ACMR')
        filepaths.extend([line.strip() for line in output.split('\n')])
        
        # Only process each path once.
        filepaths = sorted(set(filepaths))

        for filepath in filepaths:
            filepath = os.path.abspath(os.path.join(git_repo_path, filepath))
            process_if_appropriate(filepath)

    print 'git clang-format...'
    subprocess.check_output(['git', 'clang-format']).strip()
