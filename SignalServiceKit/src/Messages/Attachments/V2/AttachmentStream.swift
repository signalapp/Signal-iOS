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

    /// Byte count of the encrypted fullsize resource
    public let encryptedByteCount: UInt32
    ///  Byte count of the decrypted fullsize resource
    public let unenecryptedByteCount: UInt32

    /// For downloaded attachments, the type of content in the actual file.
    /// If a case is set it means the file contents have been validated.
    public let contentType: TSResourceContentType

    /// Filepath to the encrypted fullsize media file on local disk.
    public let localRelativeFilePath: String

    private init(
        attachment: Attachment,
        contentHash: String,
        encryptedByteCount: UInt32,
        unenecryptedByteCount: UInt32,
        contentType: TSResourceContentType,
        localRelativeFilePath: String
    ) {
        self.attachment = attachment
        self.contentHash = contentHash
        self.encryptedByteCount = encryptedByteCount
        self.unenecryptedByteCount = unenecryptedByteCount
        self.contentType = contentType
        self.localRelativeFilePath = localRelativeFilePath
    }

    public convenience init?(attachment: Attachment) {
        guard
            let contentHash = attachment.contentHash,
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
            encryptedByteCount: encryptedByteCount,
            unenecryptedByteCount: unenecryptedByteCount,
            contentType: contentType,
            localRelativeFilePath: localRelativeFilePath
        )
    }
}
