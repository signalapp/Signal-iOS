//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Attachment.ContentType {

    public var resourceType: TSResourceContentType {
        switch self {
        case .invalid:
            return .invalid
        case .file:
            return .file
        case .image(let pixelSize):
            return .image(pixelSize: .init(getCached: { pixelSize }, compute: { pixelSize }))
        case .video(let duration, let pixelSize, _):
            return .video(duration: duration, pixelSize: .init(getCached: { pixelSize }, compute: { pixelSize }))
        case .animatedImage(let pixelSize):
            return .animatedImage(pixelSize: .init(getCached: { pixelSize }, compute: { pixelSize }))
        case .audio(let duration, _):
            return .audio(duration: .init(getCached: { duration }, compute: { duration }))
        }
    }
}
