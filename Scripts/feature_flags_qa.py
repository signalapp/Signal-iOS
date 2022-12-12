#!/usr/bin/env python3
from sys import stderr
from time import sleep
from feature_flags_internal import main

if __name__ == "__main__":
    print("❗️ feature_flags_qa.py is deprecated.", file=stderr)
    print("Waiting a moment to make sure you see this message...", file=stderr)

    sleep(3)

    main()
