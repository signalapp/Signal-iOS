//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSAttachmentUpload {
    public enum Shims {
        public typealias BlurHash = _TSAttachmentUpload_BlurHashShim
    }

    public enum Wrappers {
        public typealias BlurHash = _TSAttachmentUpload_BlurHashWrapper
    }
}

// MARK: - Shims

public protocol _TSAttachmentUpload_BlurHashShim {
    func ensureBlurHash(attachmentStream: TSAttachmentStream) async throws
}

// MARK: - Wrappers

public struct _TSAttachmentUpload_BlurHashWrapper: TSAttachmentUpload.Shims.BlurHash {
    public func ensureBlurHash(attachmentStream: TSAttachmentStream) async throws {
        try await BlurHash
            .ensureBlurHash(for: attachmentStream)
            .awaitable()
    }
}
