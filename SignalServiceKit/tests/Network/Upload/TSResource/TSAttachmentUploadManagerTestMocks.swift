//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

extension TSAttachmentUpload {
    enum Mocks {
        typealias AttachmentEncrypter = _TSAttachmentUploadManager_AttachmentEncrypterMock
        typealias BlurHash = _TSAttachmentUpload_BlurHashMock
    }
}

class _TSAttachmentUpload_BlurHashMock: TSAttachmentUpload.Shims.BlurHash {
    func ensureBlurHash(attachmentStream: TSAttachmentStream) async throws {
        return
    }
}

class _TSAttachmentUploadManager_AttachmentEncrypterMock: TSAttachmentUpload.Shims.AttachmentEncrypter {

    var encryptAttachmentBlock: ((URL, URL) -> EncryptionMetadata)?
    func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata {
        return encryptAttachmentBlock!(unencryptedUrl, encryptedUrl)
    }
}

// MARK: - TSResourceStore

class TSResourceUploadStoreMock: TSResourceStoreMock, TSResourceUploadStore {
    var filename: String!
    var size: Int!
    var uploadedAttachments = [TSResourceStream]()

    override func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        return ids.map { _ in
            return TSAttachmentStream(
                contentType: "image/jpeg",
                byteCount: UInt32(size),
                sourceFilename: filename,
                caption: nil,
                attachmentType: .default,
                albumMessageId: nil
            )
        }
    }

    func updateAsUploaded(
        attachmentStream: TSResourceStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        uploadedAttachments.append(attachmentStream)
    }
}
