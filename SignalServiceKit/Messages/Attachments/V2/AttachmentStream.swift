//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
import YYImage

/// Represents a downloaded attachment with the fullsize contents available on local disk.
public class AttachmentStream {

    public let attachment: Attachment

    public let info: Attachment.StreamInfo

    /// Filepath to the encrypted fullsize media file on local disk.
    public let localRelativeFilePath: String

    // MARK: - Convenience

    public var contentHash: String { info.contentHash }
    public var encryptedFileSha256Digest: Data { info.encryptedFileSha256Digest }
    public var encryptedByteCount: UInt32 { info.encryptedByteCount }
    public var unencryptedByteCount: UInt32 { info.unencryptedByteCount }
    public var contentType: Attachment.ContentType { info.contentType }

    // MARK: - Init

    private init(
        attachment: Attachment,
        info: Attachment.StreamInfo,
        localRelativeFilePath: String
    ) {
        self.attachment = attachment
        self.info = info
        self.localRelativeFilePath = localRelativeFilePath
    }

    public convenience init?(attachment: Attachment) {
        guard
            let info = attachment.streamInfo,
            let localRelativeFilePath = attachment.localRelativeFilePath
        else {
            return nil
        }
        self.init(
            attachment: attachment,
            info: info,
            localRelativeFilePath: localRelativeFilePath
        )
    }

    public var fileURL: URL {
        // Need to solidify the directory scheme in order to
        // properly use `localRelativeFilePath`
        fatalError("Unimplemented!")
    }

    public func makeDecryptedCopy() throws -> URL {
        guard let pathExtension = MimeTypeUtil.fileExtensionForMimeType(mimeType) else {
            throw OWSAssertionError("Invalid mime type!")
        }
        let tmpURL = OWSFileSystem.temporaryFileUrl(fileExtension: pathExtension)
        try Cryptography.decryptAttachment(
            at: fileURL,
            metadata: EncryptionMetadata(
                key: info.encryptionKey,
                digest: info.encryptedFileSha256Digest,
                plaintextLength: Int(info.unencryptedByteCount)
            ),
            output: tmpURL
        )
        return tmpURL
    }

    // MARK: - Accessing file data

    public func decryptedRawData() throws -> Data {
        return try Cryptography.decryptFile(
            at: fileURL,
            metadata: .init(
                key: info.encryptionKey,
                length: Int(info.encryptedByteCount),
                plaintextLength: Int(info.unencryptedByteCount)
            )
        )
    }

    public func decryptedLongText() throws -> String {
        let data = try decryptedRawData()
        guard let text = String(data: data, encoding: .utf8) else {
            throw OWSAssertionError("Can't parse oversize text data.")
        }
        return text
    }

    public func decryptedImage() throws -> UIImage {
        switch contentType {
        case .file, .invalid, .audio:
            throw OWSAssertionError("Requesting image from non-visual attachment")
        case .image, .animatedImage:
            return try UIImage.from(self)
        case .video(_, _, let stillImageFilePath):
            // TODO: convert relative file path to absolute
            guard let stillImageFilePath else {
                throw OWSAssertionError("Still image unavailable for video")
            }
            return try UIImage.fromEncryptedFile(
                at: URL(fileURLWithPath: stillImageFilePath),
                encryptionKey: info.encryptionKey,
                plaintextLength: info.unencryptedByteCount,
                mimeType: OWSMediaUtils.videoStillFrameMimeType.rawValue
            )
        }
    }

    public func decryptedYYImage() throws -> YYImage {
        switch contentType {
        case .file, .invalid, .audio, .video:
            throw OWSAssertionError("Requesting image from non-visual attachment")
        case .image, .animatedImage:
            return try YYImage.yyImage(from: self)
        }
    }

    public func decryptedAVAsset() throws -> AVAsset {
        switch contentType {
        case .file, .invalid, .image, .animatedImage:
            throw OWSAssertionError("Requesting AVAsset from incompatible attachment")
        case .video, .audio:
            return try AVAsset.from(self)
        }
    }

    // MARK: - Thumbnails

    public func thumbnailImage(quality: AttachmentThumbnailQuality) async -> UIImage? {
        fatalError("Unimplemented!")
    }

    public func thumbnailImageSync(quality: AttachmentThumbnailQuality) -> UIImage? {
        fatalError("Unimplemented!")
    }

    public static func pointSize(pixelSize: CGSize) -> CGSize {
        let factor = 1 / UIScreen.main.scale
        return CGSize(
            width: pixelSize.width * factor,
            height: pixelSize.height * factor
        )
    }

    private static let thumbnailDimensionPointsSmall: CGFloat = 200
    private static let thumbnailDimensionPointsMedium: CGFloat = 450
    private static let thumbnailDimensionPointsMediumLarge: CGFloat = 600

    public static let thumbnailDimensionPointsForQuotedReply = thumbnailDimensionPointsSmall

    // This size is large enough to render full screen.
    private static func thumbnailDimensionPointsLarge() -> CGFloat {
        let screenSizePoints = UIScreen.main.bounds.size
        return max(screenSizePoints.width, screenSizePoints.height)
    }

    // This size is large enough to render full screen.
    public static func thumbnailDimensionPoints(
        forThumbnailQuality thumbnailQuality: AttachmentThumbnailQuality
    ) -> CGFloat {
        switch thumbnailQuality {
        case .small:
            return thumbnailDimensionPointsSmall
        case .medium:
            return thumbnailDimensionPointsMedium
        case .mediumLarge:
            return thumbnailDimensionPointsMediumLarge
        case .large:
            return thumbnailDimensionPointsLarge()
        }
    }

    // MARK: - Audio Waveform

    public func audioWaveform() -> Task<AudioWaveform, Error> {
        DependenciesBridge.shared.audioWaveformManager.audioWaveform(forAttachment: self, highPriority: false)
    }

    public func highPriorityAudioWaveform() -> Task<AudioWaveform, Error> {
        DependenciesBridge.shared.audioWaveformManager.audioWaveform(forAttachment: self, highPriority: true)
    }
}
