//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Attachment: TSResource {

    public var resourceBlurHash: String? {
        blurHash
    }

    public var resourceEncryptionKey: Data? {
        encryptionKey
    }

    public var resourceId: TSResourceId {
        fatalError("Unimplemented!")
    }

    public var concreteType: ConcreteTSResource {
        fatalError("Unimplemented!")
    }

    public func asStream() -> TSResourceStream? {
        fatalError("Unimplemented!")
    }

    public func attachmentType(forContainingMessage: TSMessage, tx: DBReadTransaction) -> TSAttachmentType {
        fatalError("Unimplemented!")
    }

    public func transitTierDownloadState(tx: DBReadTransaction) -> TSAttachmentPointerState? {
        fatalError("Unimplemented!")
    }

    public func caption(forContainingMessage: TSMessage, tx: DBReadTransaction) -> String? {
        fatalError("Unimplemented!")
    }
}
