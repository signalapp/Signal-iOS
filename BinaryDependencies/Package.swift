// swift-tools-version:6.0

//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PackageDescription

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
            url: "https://build-artifacts.signal.org/libraries/libsignal-client-ios-build-v0.106.1.xcframework.zip",
            checksum: "60baf6a3a8ee4cab82339a5e4ed4676e2119c6dc8002018f8063d6a96c195a77",
        ),
        .binaryTarget(
            name: "LibRingRTCFfi",
            url: "https://build-artifacts.signal.org/libraries/ringrtc-ios-build-v2.74.0.xcframework.zip",
            checksum: "789d702a2e0ce00da851c118e40d80bc73e4b3c7b43c6846be2210c6f6b81104",
        ),
    ],
)
