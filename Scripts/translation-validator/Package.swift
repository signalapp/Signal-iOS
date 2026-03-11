// swift-tools-version: 6.2
//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PackageDescription

let package = Package(
    name: "translation-validator",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "translation-validator",
            dependencies: [],
            path: "src",
        ),
    ],
)
