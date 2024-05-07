//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Attachment {
    /// WARNING: these values are serialized to the database; changing them is dangerous.
    public enum ContentTypeRaw: Int {
        /// MIME type indicated it should be some other non-file type but validation failed.
        /// Inspect ``Attachment/mimeType`` to determine what type it tried to be.
        case invalid = 0
        /// Some arbitrary file. Used when no other case applies.
        case file = 1
        case image = 2
        case video = 3
        case animatedImage = 4
        case audio = 5
    }

    public enum ContentType {
        /// MIME type indicated it should be some other non-file type but validation failed.
        /// Inspect ``Attachment/mimeType`` to determine what type it tried to be.
        case invalid

        /// Some arbitrary file. Used when no other case applies.
        case file

        case image(pixelSize: CGSize)
        /// `stillFrameFilePath` points at an image file encrypted with the ``Attachment``'s `encryptionKey`.
        /// If nil, no still frame is available and no attempt should be made to generate a new one.
        case video(duration: TimeInterval, pixelSize: CGSize, stillFrameFilePath: String?)
        case animatedImage(pixelSize: CGSize)
        /// `waveformFilePath` points at the ``AudioWaveform`` file encrypted
        /// with the ``Attachment``'s `encryptionKey`. If nil, no waveform is available
        /// and no attempt should be made to generate a new one.
        case audio(duration: TimeInterval, waveformFilePath: String?)
    }
}

extension Attachment.ContentTypeRaw {
    public var isImage: Bool {
        switch self {
        case .image:
            return true
        default:
            return false
        }
    }

    public var isVideo: Bool {
        switch self {
        case .video:
            return true
        default:
            return false
        }
    }

    public var isAnimatedImage: Bool {
        switch self {
        case .animatedImage:
            return true
        default:
            return false
        }
    }

    public var isVisualMedia: Bool {
        switch self {
        case .image, .video, .animatedImage:
            return true
        default:
            return false
        }
    }

    public var isAudio: Bool {
        switch self {
        case .audio:
            return true
        default:
            return false
        }
    }
}

extension Attachment.ContentType {

    public var raw: Attachment.ContentTypeRaw {
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
