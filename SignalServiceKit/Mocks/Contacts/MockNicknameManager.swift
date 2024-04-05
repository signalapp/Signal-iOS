//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockNicknameManager: NicknameManager {
    private var mockNicknames: [Int64: NicknameRecord] = [:]

    public func fetch(recipient: SignalRecipient, tx: DBReadTransaction) -> NicknameRecord? {
        recipient.id.flatMap { mockNicknames[$0] }
    }

    public func insert(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        mockNicknames[nicknameRecord.recipientRowID] = nicknameRecord
    }

    public func update(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        mockNicknames[nicknameRecord.recipientRowID] = nicknameRecord
    }

    public func delete(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        mockNicknames.removeValue(forKey: nicknameRecord.recipientRowID)
    }
}

#endif
