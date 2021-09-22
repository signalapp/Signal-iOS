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

    func testDecryptDeduplication_withoutCulling() {
        write { transaction in
            let now = Date.ows_millisecondTimestamp()
            let serviceTimestamp1: UInt64 = now
            let serviceTimestamp2: UInt64 = now + 10
            let data1 = Randomness.generateRandomBytes(16)
            let data2 = Randomness.generateRandomBytes(16)

            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction,
                                                                         skipCull: true))
            // Not a duplicate if serviceTimestamp doesn't match.
            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp2,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction,
                                                                         skipCull: true))
            // Not a duplicate if encryptedEnvelopeData doesn't match.
            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data2,
                                                                         transaction: transaction,
                                                                         skipCull: true))
            // A duplicate if both match.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction,
                                                                         skipCull: true))
            // A duplicate if both match even if you ask twice.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction,
                                                                         skipCull: true))
        }
    }

    func testDecryptDeduplication_withCullingByRecordCount() {
        write { transaction in
            let now = Date.ows_millisecondTimestamp()
            let serviceTimestamp1: UInt64 = now
            let data1 = Randomness.generateRandomBytes(16)

            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction))
            // A duplicate if both match.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction))

            // Create enough records to:
            //
            // * Overflow culling by record count.
            // * Ensure that culling is triggered afterward.
            let mockRecordCount = (MessageDecryptDeduplicationRecord.cullFrequency +
                                   UInt64(MessageDecryptDeduplicationRecord.maxRecordCount))
            for index in 0..<mockRecordCount {
                let serviceTimestamp: UInt64 = now + index
                let data = Randomness.generateRandomBytes(16)
                XCTAssertEqual(.nonDuplicate,
                               MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp,
                                                                             encryptedEnvelopeData: data,
                                                                             transaction: transaction))
            }

            // Due to culling, this is no longer a duplicate.
            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction))
        }
    }

    func testDecryptDeduplication_withCullingByTimestamp() {
        write { transaction in
            let now = Date.ows_millisecondTimestamp()
            let serviceTimestamp1: UInt64 = now
            let data1 = Randomness.generateRandomBytes(16)

            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction))
            // A duplicate if both match.
            XCTAssertEqual(.duplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction))

            // Create enough records to ensure that culling is triggered.
            let mockRecordCount = MessageDecryptDeduplicationRecord.cullFrequency
            for index in 0..<mockRecordCount {
                // "Process" an envelope new enough to trigger culling of first record by age.
                let serviceTimestamp2: UInt64 = now + index + MessageDecryptDeduplicationRecord.maxRecordAgeMs * 2
                let data2 = Randomness.generateRandomBytes(16)
                XCTAssertEqual(.nonDuplicate,
                               MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp2,
                                                                             encryptedEnvelopeData: data2,
                                                                             transaction: transaction))
            }

            // Due to culling, this is no longer a duplicate.
            XCTAssertEqual(.nonDuplicate,
                           MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp1,
                                                                         encryptedEnvelopeData: data1,
                                                                         transaction: transaction))
        }
    }

    func testCullingByRecordCount() {
        write { transaction in
            let now = Date.ows_millisecondTimestamp()
            let peakRecordCount = (MessageDecryptDeduplicationRecord.cullFrequency +
                                   UInt64(MessageDecryptDeduplicationRecord.maxRecordCount))

            // Create enough records to ensure that culling is triggered multiple times.
            let mockRecordCount = (MessageDecryptDeduplicationRecord.cullFrequency * 10 +
                                   UInt64(MessageDecryptDeduplicationRecord.maxRecordCount))
            for index in 0..<mockRecordCount {
                XCTAssertTrue(MessageDecryptDeduplicationRecord.recordCount(transaction: transaction) < peakRecordCount)

                let serviceTimestamp: UInt64 = now + index
                let data = Randomness.generateRandomBytes(16)
                XCTAssertEqual(.nonDuplicate,
                               MessageDecryptDeduplicationRecord.deduplicate(serviceTimestamp: serviceTimestamp,
                                                                             encryptedEnvelopeData: data,
                                                                             transaction: transaction))

                XCTAssertTrue(MessageDecryptDeduplicationRecord.recordCount(transaction: transaction) < peakRecordCount)
            }
        }
    }
}
