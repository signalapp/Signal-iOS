#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def parse_xcresult(data):
    # Calculate duration
    start_time = data.get("startTime")
    finish_time = data.get("finishTime")
    duration = finish_time - start_time if start_time and finish_time else 0

    # Get test counts
    total = data.get("totalTestCount", 0)
    passed = data.get("passedTests", 0)
    failed = data.get("failedTests", 0)

    # Print summary
    print()
    print("********")
    print(f"Ran {total} tests in {duration:.0f} seconds.")
    print(f"{passed} tests passed.")
    print(f"{failed} tests failed.")
    print("********")

    # Print failures if any
    failures = data.get("testFailures", [])
    if failures:
        for failure in failures:
            print()
            test_id = failure.get("testIdentifierString", "N/A")
            error = failure.get("failureText", "N/A")
            print("Test failed:")
            print(f"    {test_id}")
            print(f"    {error}")


def main():
    if len(sys.argv) < 2:
        print("Usage: parse_xcresult.py <path_to_json_file>")
        sys.exit(1)

    json_file = Path(sys.argv[1])

    try:
        with open(json_file, "r") as f:
            data = json.load(f)
        parse_xcresult(data)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
