//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
import GRDB

class MessageProcessorTest: SSKBaseTestSwift {

    // MARK: - Hooks

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Tests

    private static let sourceE164 = "+13213214321"
    private static let sourceUuid = UUID().uuidString

    private static func buildEnvelope(timestamp: UInt64, serverGuid: String) -> SSKProtoEnvelope {
        let builder = SSKProtoEnvelope.builder(timestamp: timestamp)
        builder.setServerTimestamp(timestamp)
        builder.setServerGuid(serverGuid)
        builder.setSourceE164(sourceE164)
        builder.setSourceUuid(sourceUuid)
        builder.setSourceDevice(1)
        return builder.buildIgnoringErrors()!
    }

    func testDecryptDeduplication_withoutCulling() {
        MessageDecryptDeduplicationRecord.cullCount.set(0)

        write { transaction in
            let now = Date.ows_millisecondTimestamp()
            let timestamp1: UInt64 = now
            let timestamp2: UInt64 = now + 10
            let serverGuid1 = UUID().uuidString
            let serverGuid2 = UUID().uuidString

            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp1,
                                                                                                               serverGuid: serverGuid1),
                                                                         transaction: transaction,
                                                                         skipCull: true))
            // A duplicate even if serviceTimestamp doesn't match.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp2,
                                                                                                               serverGuid: serverGuid1),
                                                                         transaction: transaction,
                                                                         skipCull: true))
            // Not a duplicate if serverGuid doesn't match.
            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp1,
                                                                                                               serverGuid: serverGuid2),
                                                                         transaction: transaction,
                                                                         skipCull: true))
            // A duplicate if both match.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp1,
                                                                                                               serverGuid: serverGuid1),
                                                                         transaction: transaction,
                                                                         skipCull: true))
            // A duplicate if both match even if you ask twice.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp1,
                                                                                                               serverGuid: serverGuid1),
                                                                         transaction: transaction,
                                                                         skipCull: true))
        }

        XCTAssertEqual(0, MessageDecryptDeduplicationRecord.cullCount.get())
    }

    func testDecryptDeduplication_withCullingByRecordCount() {
        MessageDecryptDeduplicationRecord.cullCount.set(0)

        write { transaction in
            let now = Date.ows_millisecondTimestamp()
            let timestamp1: UInt64 = now
            let timestamp2: UInt64 = now + 10
            let serverGuid1 = UUID().uuidString
            let serverGuid2 = UUID().uuidString

            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp1,
                                                                                                               serverGuid: serverGuid1),
                                                                         transaction: transaction))
            // A duplicate if both match.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp1,
                                                                                                               serverGuid: serverGuid1),
                                                                         transaction: transaction))

            // Create enough records to:
            //
            // * Overflow culling by record count.
            // * Ensure that culling is triggered afterward.
            let mockRecordCount = (MessageDecryptDeduplicationRecord.cullFrequency +
                                   UInt64(MessageDecryptDeduplicationRecord.maxRecordCount))
            for index in 0..<mockRecordCount {
                let timestamp: UInt64 = now + 25 + index
                let serverGuid = UUID().uuidString
                XCTAssertEqual(.nonDuplicate,
                               MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp,
                                                                                                                   serverGuid: serverGuid),
                                                                             transaction: transaction))
            }

            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp2,
                                                                                                               serverGuid: serverGuid2),
                                                                         transaction: transaction))

            // Due to culling, this is no longer a duplicate.
            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp1,
                                                                                                               serverGuid: serverGuid1),
                                                                         transaction: transaction))

            // Still a duplicate; not yet culled.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp2,
                                                                                                               serverGuid: serverGuid2),
                                                                         transaction: transaction))
        }
    }

    func testCullingByRecordCount() {
        MessageDecryptDeduplicationRecord.cullCount.set(0)

        write { transaction in
            let now = Date.ows_millisecondTimestamp()
            let peakRecordCount = (MessageDecryptDeduplicationRecord.cullFrequency +
                                   UInt64(MessageDecryptDeduplicationRecord.maxRecordCount))

            // Create enough records to ensure that culling is triggered multiple times.
            let mockRecordCount = (MessageDecryptDeduplicationRecord.cullFrequency * 10 +
                                   UInt64(MessageDecryptDeduplicationRecord.maxRecordCount))
            for index in 0..<mockRecordCount {
                XCTAssertTrue(MessageDecryptDeduplicationRecord.recordCount(transaction: transaction) < peakRecordCount)

                let timestamp: UInt64 = now + index
                let serverGuid = UUID().uuidString
                XCTAssertEqual(.nonDuplicate,
                               MessageDecryptDeduplicationRecord.deduplicate(encryptedEnvelope: Self.buildEnvelope(timestamp: timestamp,
                                                                                                                   serverGuid: serverGuid),
                                                                             transaction: transaction))

                XCTAssertTrue(MessageDecryptDeduplicationRecord.recordCount(transaction: transaction) < peakRecordCount)
            }
        }

        // The exact value doesn't matter; we just want to verify that the
        // behavior is deterministic and that we're not culling too often.
        XCTAssertEqual(20, MessageDecryptDeduplicationRecord.cullCount.get())
    }
}
