#!/usr/bin/env python
import sys
import os
import commands
import subprocess
import inspect    

def fail(message):
    file_name = __file__
    current_line_no = inspect.stack()[1][2]
    current_function_name = inspect.stack()[1][3]
    print 'Failure in:', file_name, current_line_no, current_function_name
    print message
    sys.exit(1)


def execute_command(command):
    try:
        print ' '.join(command)
        output = subprocess.check_output(command)
        if output:
            print output
    except subprocess.CalledProcessError as e:
        print e.output
        sys.exit(1)

def set_feature_flags(new_flags_level):
    output = subprocess.check_output(['git', 'status', '--porcelain'])
    if len(output.strip()) > 0:
        print output
        fail('Git repository has untracked files.')
    output = subprocess.check_output(['git', 'diff', '--shortstat'])
    if len(output.strip()) > 0:
        print output
        fail('Git repository has untracked files.')

    flags_path = 'SignalServiceKit/src/Util/FeatureFlags.swift'
    with open(flags_path, 'rt') as f:
        text = f.read()
    lines = text.split('\n')
    # lines = [line.strip() for line in lines]
    new_lines = []
    for line in lines:
        if line.strip().startswith('let build: FeatureBuild'):
            line = "let build: FeatureBuild = OWSIsDebugBuild() ? .dev : .%s" % ( new_flags_level, )
            new_lines.append(line)
        else:
            new_lines.append(line)
    text = '\n'.join(new_lines)
    with open(flags_path, 'wt') as f:
        f.write(text)

    output = subprocess.check_output(['git', 'status', '--porcelain'])
    if len(output.strip()) > 0:
        # git add .
        cmds = ['git', 'add', '.']
        execute_command(cmds)

        # git commit -m "Feature flags for .beta."
        cmds = ['git', 'commit', '-m', '"Feature flags for .%s."' % ( new_flags_level, )]
        execute_command(cmds)
    else:
        print "Feature flags already set to %s, nothing to do" % new_flags_level
