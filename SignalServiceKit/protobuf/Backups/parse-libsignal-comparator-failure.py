#!/usr/bin/env python3

"""
When a MessageBackupIntegrationTestCase fails due to non-matching
`LibSignalClient.ComparableBackup` instances representing the imported and
exported Backup .binprotos, those two `ComparableBackup` strings are logged.

This script expects to take, as stdin, those two lines of output. It then
parses that log output and opens a diff viewer.
"""

import json
import os
import sys
import tempfile


def dumpJsonToTempFile(jsonString: str, fileName: str) -> str:
    (fd, filePath) = tempfile.mkstemp(suffix="_{}.json".format(fileName))

    with open(fd, mode="w") as fileHandle:
        jsonObj = json.loads(jsonString)
        fileHandle.write(json.dumps(jsonObj, indent=4))

    return filePath


def diffFiles(lhs: str, rhs: str):
    editor = os.environ["EDITOR"]
    if editor is None:
        editor = "vim"

    os.execvp(editor, [editor, "-d", lhs, rhs])


def parseComparisonFailure():
    inputLines: list[str] = sys.stdin.readlines()

    if len(inputLines) != 2:
        print("Error: unexpected number of lines in input!")
        exit(1)

    sharedTestCaseBackup = inputLines[0]
    exportedBackup = inputLines[1]

    sharedTestCaseBackupCanonicalRepresentation = dumpJsonToTempFile(sharedTestCaseBackup, "sharedTestCase")
    exportedBackupCanonicalRepresentation = dumpJsonToTempFile(exportedBackup, "exported")

    diffFiles(sharedTestCaseBackupCanonicalRepresentation, exportedBackupCanonicalRepresentation)


if __name__ == "__main__":
    parseComparisonFailure()
