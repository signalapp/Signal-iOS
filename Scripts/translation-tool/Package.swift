// swift-tools-version: 5.6
//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "translation-tool",
    platforms: [.macOS(.v12)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "translation-tool",
            dependencies: [],
            path: "src"
        )
    ]
)
