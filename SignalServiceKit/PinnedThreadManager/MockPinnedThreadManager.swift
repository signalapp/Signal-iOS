//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

struct MockPinnedThreadMerger: PinnedThreadMerger {

    init() {}

    func mergeRecipientId(
        _ recipientId: SignalRecipient.RowId,
        into targetRecipientId: SignalRecipient.RowId,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        // Do nothing.
    }
}

#endif
