//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Attachment.ContentType {

    public var resourceType: TSResourceContentType {
        switch self {
        case .file:
            return .file
        case .image(let pixelSize):
            return .image(pixelSize: pixelSize)
        case .video(let duration, let pixelSize):
            return .video(duration: duration, pixelSize: pixelSize)
        case .animatedImage(let pixelSize):
            return .animatedImage(pixelSize: pixelSize)
        case .audio(let duration):
            return .audio(duration: duration)
        }
    }
}
