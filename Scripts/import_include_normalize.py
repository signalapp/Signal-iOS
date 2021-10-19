#!/usr/bin/env python2.7
# -*- coding: utf-8 -*-

import os
import sys
import subprocess
import datetime
import argparse
import commands


git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())


class Include:
    def __init__(self, line, isInclude, isQuote, body, comment):
        self.line = line
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
    
    def isSystemFrameworkOrPod(self):
        prefixes = [
            'UIKit',
            'Intents',
            'SignalCoreKit',
            'UserNotifications',
            'WebRTC',
            'Foundation',
            'PureLayout',
            'YYImage',
            'MetalKit',
            'objc',
            'SSZipArchive',
            'sys',
            'MessageUI',
            'Contacts',
            'MobileCoreServices',
            'AVKit',
            'MediaPlayer',
            'StoreKit',
            'AVFoundation',
            'XCTest',
            'Availability',
            'CocoaLumberjack',
            'AudioToolbox',
            'SignalMetadataKit',
            'Curve25519Kit',
            'Mantle',
            'CoreServices',
            'webp',
            'AFNetworking',
            'CommonCrypto',
            'libPhoneNumber_iOS',
            'openssl',
            'Photos',
            'ContactsUI',
        ]
        for prefix in prefixes:
            if self.body.startswith(prefix + '/'):
                return True
        systemFrameworkHeaders = set([
            "zlib.h",
            'Availability.h',
            'notify.h',
            'AssertMacros.h',
        ])
        return self.body in systemFrameworkHeaders


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
        return None

    comment = None
    if remainder.startswith('"'):
        isQuote = True
        endIndex = remainder.find('"', 1)
        if endIndex < 0:
            print ('Unexpected import or include: '+ line)
            sys.exit(1)
        body = remainder[1:endIndex]
        comment = remainder[endIndex+1:]
    elif remainder.startswith('<'):
        isQuote = False
        endIndex = remainder.find('>', 1)
        if endIndex < 0:
            print ('Unexpected import or include: '+ line)
            sys.exit(1)
        body = remainder[1:endIndex]
        comment = remainder[endIndex+1:]
    else:
        print ('Unexpected import or include: '+ remainder)
        sys.exit(1)

    return Include(line, isInclude, isQuote, body, comment)


class Target:
    def __init__(self, name, path, is_test_target=False):
        self.name = name
        self.path = path
        self.is_test_target = is_test_target


class Header:
    def __init__(self, targetName, path, filename):
        self.targetName = targetName
        self.path = path
        self.filename = filename


class SwiftHeader:
    def __init__(self, targetName, filename):
        self.targetName = targetName
        self.filename = filename


class HeaderSet:
    def __init__(self, targets, headers):
        self.targets = targets
        self.headers = headers
        
        headerMap = {}
        for header in headers:
            if header.filename in headerMap:
                otherHeader = headerMap[header.filename]
                print 'Header conflict:', header.filename
                print 'Header 1:', header.path
                print 'Header 2:', otherHeader.path
                sys.exit(1)
            else:
                headerMap[header.filename] = header
                
        self.headerMap = headerMap
                
        swiftHeaderMap = {}
        for target in targets:
            swiftHeader = SwiftHeader(target.name, target.name + '-Swift.h')
            swiftHeaderMap[swiftHeader.filename] = swiftHeader
        self.swiftHeaderMap = swiftHeaderMap
        

    def find_header(self, text):
        splits = text.split('/')
        filename = splits[-1]
        if filename is None or len(filename) < 1:
            return None
        print 'filename:', filename
        if filename not in self.headerMap:
            return None
        header = self.headerMap[filename]
        return header
        

    def find_swift_header(self, text):
        splits = text.split('/')
        filename = splits[-1]
        if filename is None or len(filename) < 1:
            return None
        print 'filename:', filename
        if filename not in self.swiftHeaderMap:
            return None
        header = self.swiftHeaderMap[filename]
        return header
        

def find_headers(targets):
    headers = []

    for target in targets:
        for rootdir, dirnames, filenames in os.walk(target.path):
            for filename in filenames:
                if not filename.endswith('.h'):
                    continue
                file_path = os.path.abspath(os.path.join(rootdir, filename))
                headers.append(Header(target.name, file_path, filename))
        
    return headers
    
    
def normalize_imports_and_includes(targets, headerSet):
    
    for target in targets:
        for rootdir, dirnames, filenames in os.walk(target.path):
            for filename in filenames:
                file_ext = os.path.splitext(filename)[1]
                if file_ext not in ('.h', '.hpp', '.cpp', '.m', '.mm', '.pch'):
                    continue
                file_path = os.path.abspath(os.path.join(rootdir, filename))
                normalize_imports_and_includes_in_file(targets, target, headerSet, file_path, filename)
                
    
def normalize_imports_and_includes_in_file(targets, target, headerSet, file_path, filename):

    short_filepath = file_path[len(git_repo_path):]
    if short_filepath.startswith(os.sep):
       short_filepath = short_filepath[len(os.sep):]
       
    print 'Processing:', filename

    with open(file_path, 'rt') as f:
        text = f.read()

    original_text = text

    lines = text.split('\n')

    new_lines = []
    for line in lines:
        include = parse_include(line)
        if include is None:
            new_lines.append(line)
            continue
            
        print '\t', 'include or import:', include.body
        if include.comment is not None and len(include.comment) > 0:
            print 'Invalid include or import:', include.line
            sys.exit(1)
        
        if include.isSystemFrameworkOrPod():
            new_lines.append(line)
            continue
        
        swiftHeader = headerSet.find_swift_header(include.body)
        if swiftHeader is not None:
            # NOTE: -Swift.h headers must always use long-form imports.
            newline = "#import <%s/%s>" % ( swiftHeader.targetName, swiftHeader.filename, )
            new_lines.append(newline)
            continue
        
        header = headerSet.find_header(include.body)
        if header is None:
            print
            print 'Unknown include or import:', include.line
            print 'Unknown include or import:', include.body
            print 'In file:', filename
            print 'If this is a system framework or pod, add it to isSystemFrameworkOrPod().'
            print
            sys.exit(1)

        if header.targetName == target.name:
            newline = '#import "%s"' % ( header.filename, )
        else:
            newline = "#import <%s/%s>" % ( header.targetName, header.filename, )
        new_lines.append(newline)

    lines = new_lines
    

    # shebang = ""
    # if lines[0].startswith('#!'):
    #     shebang = lines[0] + '\n'
    #     lines = lines[1:]

    # while lines and lines[0].startswith('//'):
    #     lines = lines[1:]
    text = '\n'.join(lines)
    text = text.strip()
    text = text + '\n'

    if original_text == text:
        return

    print 'Updating:', filename

    with open(file_path, 'wt') as f:
        f.write(text)
    # sys.exit(0)
    


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Normalize imports and includes script.')
    # parser.add_argument('--all', action='store_true', help='process all files in or below current dir')
    # parser.add_argument('--path', help='used to specify a path to process.')
    # parser.add_argument('--ref', help='process all files that have changed since the given ref')
    parser.add_argument('--write-header-list', action='store_true', help='Write list of repo headers to file for debugging')
    args = parser.parse_args()

    clang_format_commit = 'HEAD'

    targets = [ 
        Target('Signal', 'Signal/src'),
        Target('Signal', 'Signal/test', is_test_target=True),
        Target('SignalMessaging', 'SignalMessaging'),
        Target('SignalServiceKit', 'SignalServiceKit/src'),
        Target('SignalServiceKit', 'SignalServiceKit/tests', is_test_target=True),
        Target('SignalShareExtension', 'SignalShareExtension'),
        Target('SignalUI', 'SignalUI'),
        Target('SignalUI', 'SignalUITests', is_test_target=True),
    ]
    
    headers = find_headers(targets)    
    print 'headers:', len(headers)
    headerSet = HeaderSet(targets, headers)
    
    if args.write_header_list:
        lines = []
        for header in headers:
            lines.append(header.path)
        lines.sort()
        text = '\n'.join(lines)
        text = text + '\n'

        filename = 'import_header_paths.txt'
        file_path = os.path.abspath(os.path.join(git_repo_path, filename))
        print 'Header list:', filename
        with open(file_path, 'wt') as f:
            f.write(text)
            
        lines = []
        for header in headers:
            lines.append(header.filename)
        lines.sort()
        text = '\n'.join(lines)
        text = text + '\n'

        filename = 'import_header_filenames.txt'
        file_path = os.path.abspath(os.path.join(git_repo_path, filename))
        print 'Header list:', filename
        with open(file_path, 'wt') as f:
            f.write(text)
        
    
    normalize_imports_and_includes(targets, headerSet)    

    print 'Complete.'
