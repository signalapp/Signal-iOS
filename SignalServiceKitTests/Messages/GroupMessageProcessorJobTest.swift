//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct GroupMessageProcessorJobTest {
    @Test
    func testDeserialize() {
        let groupId = Data(repeating: 2, count: 32)
        let db = InMemoryDB()
        try! db.write { tx in
            try tx.database.execute(sql: """
            INSERT INTO "model_IncomingGroupsV2MessageJob" (
                "id",
                "uniqueId",
                "recordType",
                "createdAt",
                "envelopeData",
                "plaintextData",
                "wasReceivedByUD",
                "groupId",
                "serverDeliveryTimestamp"
            ) VALUES (
                42,
                '00000000-0000-4000-8000-000000000000',
                63,
                1744323000,
                X'1234',
                X'5678',
                1,
                X'0202020202020202020202020202020202020202020202020202020202020202',
                1744323001
            )
            """)
        }
        let job = db.read { tx in GroupMessageProcessorJobStore().nextJob(forGroupId: groupId, tx: tx)! }
        #expect(job.id == 42)
        #expect(job.groupId == groupId)
        #expect(job.envelopeData == Data([0x12, 0x34]))
        #expect(job.plaintextData == Data([0x56, 0x78]))
        #expect(job.createdAt == Date(timeIntervalSince1970: 1744323000))
        #expect(job.wasReceivedByUD == true)
        #expect(job.serverDeliveryTimestamp == 1744323001)
    }
}
