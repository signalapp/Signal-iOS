//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSAttachmentStream {

    @objc
    internal func anyDidInsertSwift(tx: SDSAnyWriteTransaction) {
        owsFailDebug("TSAttachment is obsoleted")
    }

    @objc
    internal func anyDidRemoveSwift(tx: SDSAnyWriteTransaction) {
        owsFailDebug("TSAttachment is obsoleted")
    }
}
