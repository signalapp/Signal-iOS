//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct GroupRecordTest {
    @Test
    func testSetMasterKey() throws {
        let db = InMemoryDB()
        let secretParams = try GroupSecretParams.generate()
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()
        let masterKey = try secretParams.getMasterKey()
        var groupRecord = db.write { tx in
            return GroupStore().fetchGroupOrInsert(groupId: .V2(groupId), tx: tx)
        }
        db.write { tx in
            groupRecord.setMasterKey(secretParams: secretParams, tx: tx)
        }
        try #require(groupRecord.masterKey != nil)
        groupRecord = try db.read { tx in
            return try #require(GroupStore().fetchGroup(forGroupId: groupId, tx: tx))
        }
        #expect(groupRecord.masterKey?.serialize() == masterKey.serialize())
    }

    @Test
    func testLastSnapshotAt() throws {
        let db = InMemoryDB()
        let now = Date()
        let secretParams = try GroupSecretParams.generate()
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()
        var groupRecord = db.write { tx in
            return GroupStore().fetchGroupOrInsert(secretParams: secretParams, tx: tx)
        }
        try #require(groupRecord.shouldFetchSnapshot(now: now))
        db.write { tx in
            groupRecord.setLastSnapshotAt(now, tx: tx)
        }
        #expect(!groupRecord.shouldFetchSnapshot(now: now))
        #expect(groupRecord.shouldFetchSnapshot(now: now.addingTimeInterval(.year)))
        groupRecord = try db.read { tx in
            return try #require(GroupStore().fetchGroup(forGroupId: groupId, tx: tx))
        }
        #expect(!groupRecord.shouldFetchSnapshot(now: now))
        #expect(groupRecord.shouldFetchSnapshot(now: now.addingTimeInterval(.year)))
    }

    /// Ensures that lastSnapshotVersion also influences `shouldFetchSnapshot`
    @Test
    func testLastSnapshotVersion() throws {
        let db = InMemoryDB()
        let secretParams = try GroupSecretParams.generate()
        let groupId = try secretParams.getPublicParams().getGroupIdentifier()
        var groupRecord = db.write { tx in
            return GroupStore().fetchGroupOrInsert(secretParams: secretParams, tx: tx)
        }
        let now = groupRecord.lastSnapshotAtDate
        try #require(groupRecord.shouldFetchSnapshot(now: now))
        db.write { tx in
            groupRecord.setLastSnapshotAt(now, tx: tx)
        }
        #expect(!groupRecord.shouldFetchSnapshot(now: now))
        groupRecord = try db.read { tx in
            return try #require(GroupStore().fetchGroup(forGroupId: groupId, tx: tx))
        }
        #expect(!groupRecord.shouldFetchSnapshot(now: now))
    }
}
