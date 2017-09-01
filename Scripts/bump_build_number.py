#!/usr/bin/env python
import sys
import os
import re
import commands
import subprocess

def fail(message):
    print message
    sys.exit(1)

def find_project_root():
    path = os.path.abspath(os.curdir)
    
    while True:
        # print 'path', path
        if not os.path.exists(path):
            break
        git_path = os.path.join(path, '.git')
        if os.path.exists(git_path):
            return path
        new_path = os.path.abspath(os.path.dirname(path))
        if not new_path or new_path == path:
            break
        path = new_path
    
    fail('Could not find project root path')

if __name__ == '__main__':
    project_root_path = find_project_root()
    # print 'project_root_path', project_root_path
    plist_path = os.path.join(project_root_path, 'Signal', 'Signal-Info.plist')
    if not os.path.exists(plist_path):
        fail('Could not find .plist')
        
    output = subprocess.check_output(['git', 'status', '--porcelain'])
    if len(output.strip()) > 0:
        print output
        fail('Git repository has untracked files.')
    output = subprocess.check_output(['git', 'diff', '--shortstat'])
    if len(output.strip()) > 0:
        print output
        fail('Git repository has untracked files.')
    
    # Ensure .plist is in xml format, not binary.
    output = subprocess.check_output(['plutil', '-convert', 'xml1', plist_path])
    # print 'output', output
    
    with open(plist_path, 'rt') as f:
        text = f.read()
    # print 'text', text

    # <key>CFBundleVersion</key>
    # <string>2.13.0.13</string>
    file_regex = re.compile(r'<key>CFBundleVersion</key>\s*<string>([\d\.]+)</string>', re.MULTILINE)
    file_match = file_regex.search(text)
    # print 'match', match
    if not file_match:   
        fail('Could not parse .plist')
    
    old_build_number = file_match.group(1)
    print 'old_build_number:', old_build_number
    
    build_number_regex = re.compile(r'\.(\d+)$')
    build_number_match = build_number_regex.search(old_build_number)
    if not build_number_match:   
        fail('Could not parse .plist version')
    
    build_number = build_number_match.group(1)
    build_number = str(1 + int(build_number))
    new_build_number = old_build_number[:build_number_match.start(1)] + build_number
    print 'new_build_number:', new_build_number
    
    text = text[:file_match.start(1)] + new_build_number + text[file_match.end(1):]
    with open(plist_path, 'wt') as f:
        f.write(text)
        
    output = subprocess.check_output(['git', 'add', '.'])
    output = subprocess.check_output(['git', 'commit', '-m', 'Bump build to %s.\n\n// FREEBIE' % new_build_number])
    
        
