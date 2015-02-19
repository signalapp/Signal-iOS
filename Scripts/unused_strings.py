#!/usr/bin/env sh
"""
This script can be used to grep the source to tree to see which localized strings are in use. 

author: corbett
usage: ./unused_strings.py Localizable.strings source_dir
"""
import sys
import os
import re


def file_match(fname, pat):
	try:
		f = open(fname, "rt")
	except IOError:
		return

	for i, line in enumerate(f):
		if pat.search(line):
			return True
	f.close()
	return False


def rgrep_match(dir_name, s_pat):
	pat = re.compile(s_pat)
	for dirpath, dirnames, filenames in os.walk(dir_name):
		for fname in filenames:
			fullname = os.path.join(dirpath, fname)
			match=file_match(fullname, pat)
			if match:
				return match
	return False
	
if __name__ == '__main__':
	for item in open(sys.argv[1]).readlines():
		grep_for=item.strip().split(' = ')[0].replace('"','')
		if rgrep_match(sys.argv[2],grep_for):
			print item.strip()
			