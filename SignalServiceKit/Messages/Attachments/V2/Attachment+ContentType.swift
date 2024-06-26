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

        public init(rawValue: UInt32) throws {
            guard
                let rawValue = Int(exactly: rawValue),
                let value = ContentTypeRaw(rawValue: rawValue)
            else {
                throw OWSAssertionError("Invalid raw content type")
            }
            self = value
        }
    }

    public enum ContentType {
        /// MIME type indicated it should be some other non-file type but validation failed.
        /// Inspect ``Attachment/mimeType`` to determine what type it tried to be.
        case invalid

        /// Some arbitrary file. Used when no other case applies.
        case file

        case image(pixelSize: CGSize)
        /// `stillFrameRelativeFilePath` points at an image file encrypted with the ``Attachment``'s `encryptionKey`.
        /// If nil, no still frame is available and no attempt should be made to generate a new one.
        case video(duration: TimeInterval, pixelSize: CGSize, stillFrameRelativeFilePath: String?)
        case animatedImage(pixelSize: CGSize)
        /// `waveformRelativeFilePath` points at the ``AudioWaveform`` file encrypted
        /// with the ``Attachment``'s `encryptionKey`. If nil, no waveform is available
        /// and no attempt should be made to generate a new one.
        case audio(duration: TimeInterval, waveformRelativeFilePath: String?)

        public init?(
            raw: UInt32?,
            cachedAudioDurationSeconds: Double?,
            cachedMediaHeightPixels: UInt32?,
            cachedMediaWidthPixels: UInt32?,
            cachedVideoDurationSeconds: Double?,
            audioWaveformRelativeFilePath: String?,
            videoStillFrameRelativeFilePath: String?
        ) throws {
            guard let raw else {
                return nil
            }
            let rawEnum = try ContentTypeRaw(rawValue: raw)

            func requirePixelSize() throws -> CGSize {
                guard
                    let cachedMediaWidthPixels,
                    let cachedMediaWidthPixels = Int(exactly: cachedMediaWidthPixels),
                    let cachedMediaHeightPixels,
                    let cachedMediaHeightPixels = Int(exactly: cachedMediaHeightPixels)
                else {
                    throw OWSAssertionError("Missing pixel size")
                }
                return CGSize(width: cachedMediaWidthPixels, height: cachedMediaHeightPixels)
            }

            switch rawEnum {
            case .invalid:
                self = .invalid
            case .file:
                self = .file
            case .image:
                self = .image(pixelSize: try requirePixelSize())
            case .video:
                guard
                    let cachedVideoDurationSeconds,
                    let cachedVideoDurationSeconds = Double(exactly: cachedVideoDurationSeconds)
                else {
                    throw OWSAssertionError("Missing video duration")
                }
                self = .video(
                    duration: cachedVideoDurationSeconds,
                    pixelSize: try requirePixelSize(),
                    stillFrameRelativeFilePath: videoStillFrameRelativeFilePath
                )
            case .animatedImage:
                self = .animatedImage(pixelSize: try requirePixelSize())
            case .audio:
                guard
                    let cachedAudioDurationSeconds,
                    let cachedAudioDurationSeconds = Double(exactly: cachedAudioDurationSeconds)
                else {
                    throw OWSAssertionError("Missing audio duration")
                }
                self = .audio(
                    duration: cachedAudioDurationSeconds,
                    waveformRelativeFilePath: audioWaveformRelativeFilePath
                )
            }
        }
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
