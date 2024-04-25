//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSAttachmentStream {

    @objc
    internal func anyDidInsertSwift(tx: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.mediaGalleryResourceManager.didInsert(
            attachmentStream: ReferencedTSResourceStream(
                reference: TSAttachmentReference(uniqueId: self.uniqueId, attachment: self),
                attachmentStream: self
            ),
            tx: tx.asV2Write
        )
    }

    @objc
    internal func anyDidRemoveSwift(tx: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.mediaGalleryResourceManager.didRemove(
            attachmentStream: ReferencedTSResourceStream(
                reference: TSAttachmentReference(uniqueId: self.uniqueId, attachment: self),
                attachmentStream: self
            ),
            tx: tx.asV2Write
        )
    }
}
