//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Attachment {
    /// WARNING: these values are serialized to the database; changing them is dangerous.
    /// If you do change them, you might also need to reindex the media gallery indexes:
    /// message_attachment_reference_media_gallery_visualMedia_content_type_index
    /// message_attachment_reference_media_gallery_fileOrInvalid_content_type_index
    /// _
    /// These indexes rely on the generated virtual columns isVisualMediaContentType and
    /// isInvalidOrFileContentType respectively. These columns must be redefined if the raw
    /// values of this enum change, and might need to be redefined if new cases are added.
    public enum ContentType: UInt32 {
        case file = 1
        case image = 2
        case video = 3
        case animatedImage = 4
        case audio = 5

        init(mimeType: String) {
            if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
                self = .video
            } else if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
                self = .audio
            } else if
                MimeTypeUtil.isSupportedImageMimeType(mimeType)
                || MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType)
            {
                self = .image
            } else {
                self = .file
            }
        }
    }
}

extension Attachment.ContentType {
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
