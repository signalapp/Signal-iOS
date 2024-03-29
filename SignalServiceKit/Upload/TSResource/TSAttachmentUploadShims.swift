//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSAttachmentUpload {
    public enum Shims {
        public typealias AttachmentEncrypter = _TSAttachmentUpload_AttachmentEncrypterShim
        public typealias BlurHash = _TSAttachmentUpload_BlurHashShim
    }

    public enum Wrappers {
        public typealias AttachmentEncrypter = _TSAttachmentUpload_AttachmentEncrypterWrapper
        public typealias BlurHash = _TSAttachmentUpload_BlurHashWrapper
    }
}

// MARK: - Shims

public protocol _TSAttachmentUpload_AttachmentEncrypterShim {
    func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata
}

public protocol _TSAttachmentUpload_BlurHashShim {
    func ensureBlurHash(attachmentStream: TSAttachmentStream) async throws
}

// MARK: - Wrappers

public struct _TSAttachmentUpload_AttachmentEncrypterWrapper: TSAttachmentUpload.Shims.AttachmentEncrypter {
    public func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata {
        try Cryptography.encryptAttachment(at: unencryptedUrl, output: encryptedUrl)
    }
}

public struct _TSAttachmentUpload_BlurHashWrapper: TSAttachmentUpload.Shims.BlurHash {
    public func ensureBlurHash(attachmentStream: TSAttachmentStream) async throws {
        try await BlurHash
            .ensureBlurHash(for: attachmentStream)
            .awaitable()
    }
}
