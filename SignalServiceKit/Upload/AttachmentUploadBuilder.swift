//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

internal struct AttachmentUploadBuilder: UploadBuilder {

    private let attachmentStream: AttachmentStream

    public init(
        attachmentStream: AttachmentStream
    ) {
        self.attachmentStream = attachmentStream
    }

    func buildMetadata() throws -> Upload.LocalUploadMetadata {
        return Upload.LocalUploadMetadata(
            fileUrl: attachmentStream.fileURL,
            key: attachmentStream.attachment.encryptionKey,
            digest: attachmentStream.encryptedFileSha256Digest,
            encryptedDataLength: Int(clamping: attachmentStream.encryptedByteCount),
            plaintextDataLength: Int(clamping: attachmentStream.unenecryptedByteCount)
        )
    }
}
