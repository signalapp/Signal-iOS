//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentBackupThumbnail {
    public let attachment: Attachment

    /// Filepath to the encrypted thumbnail file on local disk.
    public let localRelativeFilePathThumbnail: String

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
}
