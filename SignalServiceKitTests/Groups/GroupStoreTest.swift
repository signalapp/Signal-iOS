//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct GroupStoreTest {
    @Test
    func testFetchOrInsert() throws {
        let db = InMemoryDB()
        let secretParams = try GroupSecretParams.generate()
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()
        try db.write { tx in
            try tx.database.execute(sql: "INSERT INTO GroupRecord (groupId) VALUES (?)", arguments: [groupId.serialize()])
            let groupRecord = GroupStore().fetchGroupOrInsert(secretParams: secretParams, tx: tx)
            #expect(groupRecord.groupId == groupId.serialize())
            #expect(groupRecord.masterKey != nil)
        }
    }
}
