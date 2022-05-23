#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys

ENV_NAME = "SIGNAL_IOS_DSYMS"


def run(args):
    return subprocess.run(
        args, capture_output=True, check=True, encoding="utf8"
    ).stdout.rstrip()


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Symbolicates .ips files passed as arguments. "
            "The symbolicated file is written to *.symbolicated.ips. "
            f"The script assumes you’ve saved the dSYM files in ${ENV_NAME}."
        )
    )
    parser.add_argument(
        "--open",
        "-o",
        action="store_true",
        help="Open files after they’re symbolicated.",
    )
    parser.add_argument(
        "path",
        nargs="+",
        metavar="log.ips",
        help="Paths to files that should be symbolicated.",
    )
    return parser.parse_args()


def get_version(path):
    with open(path, "r") as file:
        content = file.read()

    _, _, remainder = content.partition("\n")
    try:
        # The new format has a second JSON payload.
        json.loads(remainder)
        return 2
    except json.decoder.JSONDecodeError:
        return 1


SCRIPT_PATH_V1 = "Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/symbolicatecrash"


def symbolicate_v1(xcode_path, path, output_path):
    script_path = os.path.join(xcode_path, SCRIPT_PATH_V1)
    args = [script_path, path]
    env = {**os.environ, "DEVELOPER_DIR": xcode_path}
    with open(output_path, "wb") as file:
        subprocess.run(args, check=True, stdout=file, env=env)


SCRIPT_PATH_V2 = "Contents/SharedFrameworks/CoreSymbolicationDT.framework/Resources/CrashSymbolicator.py"


def symbolicate_v2(xcode_path, path, output_path):
    script_path = os.path.join(xcode_path, SCRIPT_PATH_V2)
    # Don’t put this on the Desktop or in Documents -- the script can’t find it there.
    # This directory is searched recursively for .dSYM files.
    symbols_path = os.getenv(ENV_NAME)
    if symbols_path is None or not os.path.exists(symbols_path):
        print(
            f"\nThe {ENV_NAME} environment variable should be set to a directory containing .dSYM files.\n",
            file=sys.stderr,
        )
        exit(1)
    args = [
        "python3",
        script_path,
        "--dsym",
        symbols_path,
        "--output",
        output_path,
        "--pretty",
        path,
    ]
    subprocess.run(args, check=True)


def main():
    ns = parse_args()

    dev_path = run(["xcode-select", "-p"])
    xcode_path = os.path.normpath(os.path.join(dev_path, *([os.pardir] * 2)))

    for path in ns.path:
        version = get_version(path)
        base, ext = os.path.splitext(path)
        output_path = base + ".symbolicated" + ext
        if version == 2:
            symbolicate_v2(xcode_path, path, output_path)
        else:
            symbolicate_v1(xcode_path, path, output_path)
        if ns.open:
            subprocess.run(["open", output_path], check=True)


if __name__ == "__main__":
    main()
