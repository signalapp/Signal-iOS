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
    
    
def process(filepath, macros):

    short_filepath = filepath[len(git_repo_path):]
    if short_filepath.startswith(os.sep):
       short_filepath = short_filepath[len(os.sep):] 
    
    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        return
    if filename == 'OWSAnalytics.h':
        return
    file_ext = os.path.splitext(filename)[1]
    
    is_swift = file_ext in ('.swift')
    
    if is_swift:
        macros = macros + ['OWSProdCallAssertionError',]
        # print 'macros', macros
    
    if file_ext in ('.swift'):
        # env_copy = os.environ.copy()
        # env_copy["SCRIPT_INPUT_FILE_COUNT"] = "1"
        # env_copy["SCRIPT_INPUT_FILE_0"] = '%s' % ( short_filepath, )
        # lint_output = subprocess.check_output(['swiftlint', 'autocorrect', '--use-script-input-files'], env=env_copy)
        # print lint_output
        # try:
        #     lint_output = subprocess.check_output(['swiftlint', 'lint', '--use-script-input-files'], env=env_copy)
        # except subprocess.CalledProcessError, e:
        #     lint_output = e.output
        # print lint_output
        pass
    
    # print short_filepath, is_swift
    
    with open(filepath, 'rt') as f:
        text = f.read()
    
    position = 0
    has_printed_filename = False
    while True:
        best_match = None
        best_macro = None
        for macro in macros:
            pattern = r'''%s\(([^,\)]+)[,\)]''' % macro
            # print '\t pattern', pattern
            matcher = re.compile(pattern)
            # matcher = re.compile(r'#define (OWSProd)')
            match = matcher.search(text, pos=position)
            if match:
                event_name = match.group(1).strip()
                
                # Ignore swift func definitions
                if is_swift and ':' in event_name:
                    continue
                    
                # print '\t', 'event_name', event_name
                
                if not best_match:
                    pass
                elif best_match.start(1) > match.start(1):
                    pass
                else:
                    continue

                best_match = match
                best_macro = macro
        # TODO:
        if not best_match:
            break
            
        event_name = best_match.group(1).strip()
        if not has_printed_filename:
            has_printed_filename = True
            print short_filepath
        print '\t', 'event_name', event_name
        position = best_match.end(1)
                
        # macros.append(macro)
        
        # break
    
    return
    
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
    
    
def process_if_appropriate(filepath, macros):
    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        return
    file_ext = os.path.splitext(filename)[1]
    if file_ext not in ('.h', '.hpp', '.cpp', '.m', '.mm', '.pch', '.swift'):
        return
    if should_ignore_path(filepath):
        return
    process(filepath, macros)

    
def extract_macros(filepath):

    macros = []
    
    with open(filepath, 'rt') as f:
        text = f.read()
    
    lines = text.split('\n')
    for line in lines:
        # Match lines of this form: 
        # #define OWSProdCritical(__eventName) ...
        matcher = re.compile(r'#define (OWSProd[^\(]+)\(.+[,\)]')
        # matcher = re.compile(r'#define (OWSProd)')
        match = matcher.search(line)
        if match:
            macro = match.group(1).strip()
            # print 'macro', macro
            macros.append(macro)
    
    return macros
    
    
if __name__ == "__main__":
    # print 'git_repo_path', git_repo_path
    
    macros_header_file_path = os.path.join(git_repo_path, 'SignalServiceKit', 'src', 'Util', 'OWSAnalytics.h')
    if not os.path.exists(macros_header_file_path):
        print 'Macros header does not exist:', macros_header_file_path
        sys.exit(1)
    macros = extract_macros(macros_header_file_path)
    print 'macros:', macros
    
    for rootdir, dirnames, filenames in os.walk(git_repo_path):
        for filename in filenames:
            file_path = os.path.abspath(os.path.join(rootdir, filename))
            process_if_appropriate(file_path, macros)
