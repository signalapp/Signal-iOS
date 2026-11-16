//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockNicknameManager: NicknameManager {
    private var mockNicknames: [SignalRecipient.RowId: NicknameRecord] = [:]

    public func fetchNickname(for recipient: SignalRecipient, tx: DBReadTransaction) -> NicknameRecord? {
        return mockNicknames[recipient.id]
    }

    public func createOrUpdate(
        nicknameRecord: NicknameRecord,
        updateStorageServiceFor recipientUniqueId: RecipientUniqueId?,
        tx: DBWriteTransaction,
    ) {
        self.insert(nicknameRecord, tx: tx)
    }

    func insert(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        mockNicknames[nicknameRecord.recipientRowID] = nicknameRecord
    }

    public func deleteNickname(
        recipientRowID: SignalRecipient.RowId,
        updateStorageServiceFor recipientUniqueId: RecipientUniqueId?,
        tx: DBWriteTransaction,
    ) {
        mockNicknames.removeValue(forKey: recipientRowID)
    }
}

#endif
