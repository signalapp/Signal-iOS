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
    func isValidVisualMedia(_ attachment: TSAttachmentStream) -> Bool

    func thumbnailImageSmallSync(_ attachment: TSAttachmentStream) -> UIImage?

    func computeBlurHashSync(for image: UIImage) throws -> String

    func update(_ attachment: TSAttachment, withBlurHash: String, tx: DBWriteTransaction)
}

// MARK: - Wrappers

public struct _TSAttachmentUpload_BlurHashWrapper: TSAttachmentUpload.Shims.BlurHash {

    public func isValidVisualMedia(_ attachment: TSAttachmentStream) -> Bool {
        return attachment.isValidVisualMedia
    }

    public func thumbnailImageSmallSync(_ attachment: TSAttachmentStream) -> UIImage? {
        return attachment.thumbnailImageSmallSync()
    }

    public func computeBlurHashSync(for image: UIImage) throws -> String {
        return try BlurHash.computeBlurHashSync(for: image)
    }

    public func update(_ attachment: TSAttachment, withBlurHash blurHash: String, tx: DBWriteTransaction) {
        attachment.update(withBlurHash: blurHash, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
