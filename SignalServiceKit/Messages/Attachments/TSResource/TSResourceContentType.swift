//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// No need to redefine this simple type.
public typealias TSResourceContentTypeRaw = Attachment.ContentTypeRaw

public enum TSResourceContentType {
    /// MIME type indicated it should be some other non-file type but validation failed.
    /// Inspect ``TSResource/mimeType`` to determine what type it tried to be.
    case invalid

    /// Some arbitrary file. Used when no other case applies.
    case file

    case image(pixelSize: Metadata<CGSize>)
    /// We have never computed video duration on the fly for TSAttachments;
    /// we either had it or we didn't. So its not wrapped in a Metadata like the others.
    case video(duration: TimeInterval?, pixelSize: Metadata<CGSize>)
    case animatedImage(pixelSize: Metadata<CGSize>)
    case audio(duration: Metadata<TimeInterval>)

    public struct Metadata<T> {
        /// Get the cached value for the metadata, if available.
        public let getCached: () -> T?
        /// Compute the value for the metadata or use the cache if available.
        public let compute: () -> T
    }
}

extension TSResourceContentType {

    public var raw: TSResourceContentTypeRaw {
        switch self {
        case .invalid:
            return .invalid
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
    public var isVisualMedia: Bool { raw.isVisualMedia }
    public var isAudio: Bool { raw.isAudio }
}
