#!/usr/bin/env python3
#
# Copyright 2026 Signal Messenger, LLC
# SPDX-License-Identifier: AGPL-3.0-only
#

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RINGRTC_LINK = REPO / "ringrtc"
WORKSPACE = REPO / "Signal-LocalRingRTC.xcworkspace"


def require_xcode_quit():
    if subprocess.run(["pgrep", "-xq", "Xcode"]).returncode == 0:
        sys.exit("error: quit Xcode first")


def cleanup():
    require_xcode_quit()
    if RINGRTC_LINK.is_symlink():
        RINGRTC_LINK.unlink()
        print(f"Removed {RINGRTC_LINK}")
    elif RINGRTC_LINK.exists():
        sys.exit(f"error: {RINGRTC_LINK} isn't a symlink; not removing it")
    if WORKSPACE.exists():
        shutil.rmtree(WORKSPACE)
        print(f"Removed {WORKSPACE}")


def main():
    parser = argparse.ArgumentParser(
        description="Open Signal in Xcode using a local RingRTC checkout.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "ringrtc",
        nargs="?",
        type=Path,
        default=REPO.parent / "ringrtc-private",
        help="path to the local RingRTC",
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="remove the ringrtc symlink and local workspace, going back to the remote RingRTC",
    )
    args = parser.parse_args()

    if args.cleanup:
        cleanup()
        return

    ringrtc = args.ringrtc.resolve()

    if not (ringrtc / "Package.swift").is_file():
        sys.exit(f"error: no RingRTC checkout at {ringrtc}")
    if not (ringrtc / "out/release/LibRingRTCFfi.xcframework").is_dir():
        sys.exit(
            f"error: build the FFI first: (cd {ringrtc} && ./bin/build-ios --ringrtc-only)"
        )
    require_xcode_quit()

    RINGRTC_LINK.unlink(missing_ok=True)
    RINGRTC_LINK.symlink_to(ringrtc)

    shutil.rmtree(WORKSPACE, ignore_errors=True)
    shutil.copytree(REPO / "Signal.xcworkspace", WORKSPACE)
    contents = WORKSPACE / "contents.xcworkspacedata"
    contents.write_text(
        contents.read_text().replace(
            "</Workspace>",
            '   <FileRef\n      location = "group:ringrtc">\n   </FileRef>\n</Workspace>',
        )
    )

    env = [
        "SIGNAL_RINGRTC_FFI_XCFRAMEWORK=../ringrtc/out/release/LibRingRTCFfi.xcframework"
    ]
    if (ringrtc / "out/release/WebRTC.xcframework").is_dir():
        env.append("RINGRTC_WEBRTC_XCFRAMEWORK=out/release/WebRTC.xcframework")

    developer_dir = subprocess.run(
        ["xcode-select", "-p"], check=True, capture_output=True, encoding="utf8"
    ).stdout.strip()
    subprocess.run(
        ["open", "-a", Path(developer_dir).parent.parent]
        + [arg for var in env for arg in ("--env", var)]
        + [WORKSPACE],
        check=True,
    )


if __name__ == "__main__":
    main()
