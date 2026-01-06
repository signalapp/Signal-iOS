//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Wrapper around OrphanedAttachmentRecord table for reads/writes.
public struct OrphanedAttachmentStore {
    public init() {}

    public func orphanAttachmentExists(
        with id: OrphanedAttachmentRecord.RowId,
        tx: DBReadTransaction,
    ) -> Bool {
        return failIfThrows {
            return try OrphanedAttachmentRecord.exists(tx.database, key: id)
        }
    }
}
