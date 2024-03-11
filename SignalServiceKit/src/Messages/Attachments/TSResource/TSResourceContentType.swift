//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// No need to redefine this simple type.
public typealias TSResourceContentTypeRaw = Attachment.ContentTypeRaw

public enum TSResourceContentType {
    /// Some arbitrary file. Used when no other case applies.
    case file

    case image(pixelSize: CGSize?)
    case video(duration: TimeInterval?, pixelSize: CGSize?)
    case animatedImage(pixelSize: CGSize?)
    case audio(duration: TimeInterval?)
}

extension TSResourceContentType {

    public var raw: TSResourceContentTypeRaw {
        switch self {
        case .file:
            return .file
        case .image:
            return .image
        case .video:
            return .video
        case .animatedImage:
            return .animatedImage
        case .audio:
            return .audio
        }
    }

    public var isImage: Bool { raw.isImage }
    public var isVideo: Bool { raw.isVideo }
    public var isAnimatedImage: Bool { raw.isAnimatedImage }
    public var isAudio: Bool { raw.isAudio }
}
