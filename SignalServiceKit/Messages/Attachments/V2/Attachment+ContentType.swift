//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Attachment {
    public enum ContentTypeRaw: Int {
        /// Some arbitrary file. Used when no other case applies.
        case file = 0
        case image = 1
        case video = 2
        case animatedImage = 3
        case audio = 4
    }

    public enum ContentType {
        /// Some arbitrary file. Used when no other case applies.
        case file

        case image(pixelSize: CGSize)
        case video(duration: TimeInterval, pixelSize: CGSize)
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
