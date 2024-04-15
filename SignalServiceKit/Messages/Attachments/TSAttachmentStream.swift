//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSAttachmentStream {

    @objc
    internal func anyDidInsertSwift(tx: SDSAnyWriteTransaction) {
        MediaGalleryResourceManager.didInsert(attachmentStream: self, transaction: tx)
    }

    @objc
    internal func anyDidRemoveSwift(tx: SDSAnyWriteTransaction) {
        MediaGalleryResourceManager.didRemove(attachmentStream: self, transaction: tx)
    }
}
