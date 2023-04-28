#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys

ENV_NAME = "SIGNAL_IOS_DSYMS"


def error_and_die(to_log):
    print(file=sys.stderr)
    print(to_log, file=sys.stderr)
    print(file=sys.stderr)
    sys.exit(1)


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


def parse_json_v2(path):
    # The new format has a second JSON payload.
    with open(path, "rb") as file:
        next(file)
        return json.load(file)


def get_version(path):
    try:
        parse_json_v2(path)
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
        error_and_die(
            f"The {ENV_NAME} environment variable should be set to a directory containing .dSYM files."
        )
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


def omit(d, key_to_remove):
    return {key: value for key, value in d.items() if key != key_to_remove}


def ensure_symbolication_happened_v2(path, output_path):
    def equal(a, b):
        """
        Like `==` but ignores changes to `symbolLocation` because those can
        change even if symbolication didn't happen.
        """
        if not isinstance(a, type(b)):
            return False
        if isinstance(a, dict):
            cleaned_a = omit(a, "symbolLocation")
            cleaned_b = omit(b, "symbolLocation")
            if len(cleaned_a) != len(cleaned_b):
                return False
            for key, a_value in cleaned_a.items():
                if key not in cleaned_b:
                    return False
                b_value = cleaned_b[key]
                if not equal(a_value, b_value):
                    return False
            return True
        if isinstance(a, list):
            if len(a) != len(b):
                return False
            for a_item, b_item in zip(a, b):
                if not equal(a_item, b_item):
                    return False
            return True
        return a == b

    original = parse_json_v2(path)
    allegedly_symbolicated = parse_json_v2(output_path)
    if equal(original, allegedly_symbolicated):
        error_and_die(
            "Nothing happened when you symbolicated. Do you have the version downloaded in the right place? Did you extract the relevant dSYMs.zip?"
        )


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
            ensure_symbolication_happened_v2(path, output_path)
        else:
            symbolicate_v1(xcode_path, path, output_path)
        if ns.open:
            subprocess.run(["open", output_path], check=True)


if __name__ == "__main__":
    main()
