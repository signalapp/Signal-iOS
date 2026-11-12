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
            url: "https://build-artifacts.signal.org/libraries/libsignal-client-ios-build-v0.107.0.xcframework.zip",
            checksum: "c21686be0c5444a3e297ca8d1338428b951060319ab0b5adb647681650785712",
        ),
        ringRTCFfi,
    ],
)
