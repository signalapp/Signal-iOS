//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

internal struct TransientUploadBuilder: UploadBuilder {

    private let source: DataSource

    private let attachmentEncrypter: Upload.Shims.AttachmentEncrypter
    private let fileSystem: Upload.Shims.FileSystem

    public init(
        source: DataSource,
        attachmentEncrypter: Upload.Shims.AttachmentEncrypter,
        fileSystem: Upload.Shims.FileSystem
    ) {
        self.source = source
        self.attachmentEncrypter = attachmentEncrypter
        self.fileSystem = fileSystem
    }

    func buildMetadata() throws -> Upload.LocalUploadMetadata {
        let temporaryFile = fileSystem.temporaryFileUrl()
        guard let sourceURL = source.dataUrl else {
            throw OWSAssertionError("Failed to access data source file")
        }
        let metadata = try attachmentEncrypter.encryptAttachment(at: sourceURL, output: temporaryFile)

        guard let length = metadata.length, let plaintextLength = metadata.plaintextLength else {
            throw OWSAssertionError("Missing length.")
        }

        guard let digest = metadata.digest else {
            throw OWSAssertionError("Digest missing for attachment.")
        }

        return Upload.LocalUploadMetadata(
            fileUrl: temporaryFile,
            key: metadata.key,
            digest: digest,
            encryptedDataLength: length,
            plaintextDataLength: plaintextLength
        )
    }
}
