//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentBackupThumbnail {
    public let attachment: Attachment

    /// Filepath to the encrypted thumbnail file on local disk.
    public let localRelativeFilePathThumbnail: String

    public var id: Attachment.IDType { attachment.id }

    // MARK: Convenience

    public var image: UIImage? { try? UIImage.from(self) }

    // MARK: - Init

    private init(
        attachment: Attachment,
        localRelativeFilePathThumbnail: String
    ) {
        self.attachment = attachment
        self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
    }

    public convenience init?(attachment: Attachment) {
        guard
            let thumbnailPath = attachment.localRelativeFilePathThumbnail
        else {
            return nil
        }
        self.init(
            attachment: attachment,
            localRelativeFilePathThumbnail: thumbnailPath
        )
    }

    public var fileURL: URL {
        return AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: self.localRelativeFilePathThumbnail)
    }

    public func decryptedRawData() throws -> Data {
        // hmac and digest are validated at download time; no need to revalidate every read.
        return try Cryptography.decryptFileWithoutValidating(
            at: fileURL,
            metadata: .init(key: attachment.encryptionKey)
        )
    }

    public static func thumbnailMediaName(fullsizeMediaName: String) -> String {
        return fullsizeMediaName + "_thumbnail"
    }

    public static func canBeThumbnailed(_ attachment: Attachment) -> Bool {
        guard let stream = attachment.asStream() else {
            // All we have to go off is mimeType and whether we had a thumbnail before.
            return MimeTypeUtil.isSupportedVisualMediaMimeType(attachment.mimeType)
                || attachment.thumbnailMediaTierInfo != nil
        }

        switch stream.contentType {
        case .invalid, .file, .audio:
            return false
        case .image(let pixelSize):
            // If the image itself is small enough to fit the thumbnail
            // size, no need for a thumbnail.
            return pixelSize.largerAxis > AttachmentThumbnailQuality.backupThumbnailDimensionPixels
        case .video, .animatedImage:
            // Visual but require conversion to still image.
            return true
        }
    }
}
