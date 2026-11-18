// swift-tools-version:6.0

//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PackageDescription

let ringRTCFfi: Target = if let path = Context.environment["SIGNAL_RINGRTC_FFI_XCFRAMEWORK"] {
    .binaryTarget(name: "LibRingRTCFfi", path: path)
} else {
    .binaryTarget(
        name: "LibRingRTCFfi",
        url: "https://build-artifacts.signal.org/libraries/ringrtc-ios-build-v2.75.0.xcframework.zip",
        checksum: "937d04db640cb86ffbfdfe8b92ada32d22469c2b5f451ab071ff8dd32518ed19",
    )
}

let package = Package(
    name: "BinaryDependencies",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "LibSignalFfi", targets: ["LibSignalFfi"]),
        .library(name: "LibRingRTCFfi", targets: ["LibRingRTCFfi"]),
    ],
    targets: [
        .binaryTarget(
            name: "LibSignalFfi",
            url: "https://build-artifacts.signal.org/libraries/libsignal-client-ios-build-v0.108.1.xcframework.zip",
            checksum: "1a1ebf8b50a9f885ae0d336b1aaa5d0d1b984794ef9280b20df11c3156a896cb",
        ),
        ringRTCFfi,
    ],
)
