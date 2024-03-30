//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents a downloaded attachment with the fullsize contents available on local disk.
public class AttachmentStream {

    public let attachment: Attachment

    /// Sha256 hash of the plaintext of the media content. Used to deduplicate incoming media.
    public let contentHash: String

    /// File digest info.
    ///
    /// SHA256Hash(iv + cyphertext + hmac),
    /// (iv + cyphertext + hmac) is the thing we actually upload to the CDN server, which uses
    /// the ``encryptionKey`` field.
    ///
    /// Generated locally/validated for downloaded attachments.
    /// For undownloaded attachments, taken off the service proto. If validation fails when
    /// downloading, the download is rejected.
    ///
    /// May be null if restored from a backup, or for legacy attachments. In this case, validation
    /// should be ignored.
    public let encryptedFileSha256Digest: Data

    /// Byte count of the encrypted fullsize resource
    public let encryptedByteCount: UInt32
    ///  Byte count of the decrypted fullsize resource
    public let unenecryptedByteCount: UInt32

    /// For downloaded attachments, the type of content in the actual file.
    /// If a case is set it means the file contents have been validated.
    public let contentType: Attachment.ContentType

    /// Filepath to the encrypted fullsize media file on local disk.
    public let localRelativeFilePath: String

    private init(
        attachment: Attachment,
        contentHash: String,
        encryptedFileSha256Digest: Data,
        encryptedByteCount: UInt32,
        unenecryptedByteCount: UInt32,
        contentType: Attachment.ContentType,
        localRelativeFilePath: String
    ) {
        self.attachment = attachment
        self.contentHash = contentHash
        self.encryptedFileSha256Digest = encryptedFileSha256Digest
        self.encryptedByteCount = encryptedByteCount
        self.unenecryptedByteCount = unenecryptedByteCount
        self.contentType = contentType
        self.localRelativeFilePath = localRelativeFilePath
    }

    public convenience init?(attachment: Attachment) {
        guard
            let contentHash = attachment.contentHash,
            let encryptedFileSha256Digest = attachment.encryptedFileSha256Digest,
            let encryptedByteCount = attachment.encryptedByteCount,
            let unenecryptedByteCount = attachment.unenecryptedByteCount,
            let contentType = attachment.contentType,
            let localRelativeFilePath = attachment.localRelativeFilePath
        else {
            return nil
        }
        self.init(
            attachment: attachment,
            contentHash: contentHash,
            encryptedFileSha256Digest: encryptedFileSha256Digest,
            encryptedByteCount: encryptedByteCount,
            unenecryptedByteCount: unenecryptedByteCount,
            contentType: contentType,
            localRelativeFilePath: localRelativeFilePath
        )
    }

    public var fileURL: URL {
        // Need to solidify the directory scheme in order to
        // properly use `localRelativeFilePath`
        fatalError("Unimplemented!")
    }

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
    private static func thumbnailDimensionPoints(forThumbnailQuality thumbnailQuality: TSAttachmentThumbnailQuality) -> CGFloat {
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
}

public class MockAttachmentStream: AttachmentStream {

    public static func mock(
        encryptedByteCount: UInt32? = nil,
        unenecryptedByteCount: UInt32? = nil
    ) -> MockAttachmentStream {
        let contentHash: String = ""
        let encryptedFileSha256Digest: Data = UInt8.random(in: 0..<(.max)).bigEndianData
        let encryptedByteCount: UInt32 = encryptedByteCount ?? UInt32.random(in: 0..<(.max))
        let unenecryptedByteCount: UInt32 = unenecryptedByteCount ?? UInt32.random(in: 0..<(.max))
        let contentType: Attachment.ContentType = .file
        let localRelativeFilePath: String = "/some/file/path"

        let attachment = MockAttachment.mock(
            contentHash: contentHash,
            encryptedFileSha256Digest: encryptedFileSha256Digest,
            encryptedByteCount: encryptedByteCount,
            unenecryptedByteCount: unenecryptedByteCount,
            contentType: contentType,
            localRelativeFilePath: localRelativeFilePath
        )
        return MockAttachmentStream(attachment: attachment)!
    }

    public override var fileURL: URL {
        return URL(string: localRelativeFilePath)!
    }
}
