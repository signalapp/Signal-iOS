//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit
@testable import Signal
@testable import SignalMessaging

class YDBToGRDBMigrationModelTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func randomStickerPackInfo() -> StickerPackInfo {
        let packId = Randomness.generateRandomBytes(16)
        let packKey = Randomness.generateRandomBytes(Int32(StickerManager.packKeyLength))

        return StickerPackInfo(packId: packId, packKey: packKey)
    }

    func randomKnownStickerPack() -> KnownStickerPack {
        return KnownStickerPack(info: randomStickerPackInfo())
    }

    func testKnownStickerPack() {
        let model1 = randomKnownStickerPack()
        let model2 = randomKnownStickerPack()
        let model3 = randomKnownStickerPack()

        self.yapRead { transaction in
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction.asAnyRead))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction.asAnyRead))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction.asAnyRead))
            XCTAssertEqual(0, KnownStickerPack.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction))
            XCTAssertEqual(0, KnownStickerPack.anyCount(transaction: transaction))
        }

        self.yapWrite { transaction in
            model1.anyInsert(transaction: transaction.asAnyWrite)
            model2.anyInsert(transaction: transaction.asAnyWrite)
            // Don't insert 3.
        }

        self.yapRead { transaction in
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction.asAnyRead))
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction.asAnyRead))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction.asAnyRead))
            XCTAssertEqual(2, KnownStickerPack.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction))
            XCTAssertEqual(0, KnownStickerPack.anyCount(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBUnorderedRecordMigrator<KnownStickerPack>(label: "KnownStickerPack", ydbTransaction: ydbTransaction, memorySamplerRatio: 0.2)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.yapRead { transaction in
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction.asAnyRead))
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction.asAnyRead))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction.asAnyRead))
            XCTAssertEqual(2, KnownStickerPack.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model1.info), transaction: transaction))
            XCTAssertNotNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model2.info), transaction: transaction))
            XCTAssertNil(KnownStickerPack.anyFetch(uniqueId: KnownStickerPack.uniqueId(for: model3.info), transaction: transaction))
            XCTAssertEqual(2, KnownStickerPack.anyCount(transaction: transaction))
        }
    }

    func testJobs() {
        // SSKMessageDecryptJobRecord
        let messageDecryptData1 = Randomness.generateRandomBytes(1024)
        let messageDecryptData2 = Randomness.generateRandomBytes(1024)
        // OWSSessionResetJobRecord
        let contactThread1 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334444"))
        let contactThread2 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334445"))

        // SSKMessageDecryptJobRecord
        let messageDecryptJobFinder = AnyJobRecordFinder<SSKMessageDecryptJobRecord>()
        let messageDecryptJobQueue = SSKMessageDecryptJobQueue()
        // OWSSessionResetJobRecord
        let sessionResetJobFinder = AnyJobRecordFinder<OWSSessionResetJobRecord>()
        let sessionResetJobQueue = SessionResetJobQueue()

        self.yapRead { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
        }

        self.yapWrite { transaction in
            // SSKMessageDecryptJobRecord
            messageDecryptJobQueue.add(envelopeData: messageDecryptData1, transaction: transaction.asAnyWrite)
            messageDecryptJobQueue.add(envelopeData: messageDecryptData2, transaction: transaction.asAnyWrite)
            // OWSSessionResetJobRecord
            sessionResetJobQueue.add(contactThread: contactThread1, transaction: transaction.asAnyWrite)
            sessionResetJobQueue.add(contactThread: contactThread2, transaction: transaction.asAnyWrite)
        }

        self.yapRead { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNotNil(messageDecryptJobFinder.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([messageDecryptData1, messageDecryptData2 ], messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            XCTAssertNotNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId ], sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.contactThreadId })
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                GRDBJobRecordMigrator(ydbTransaction: ydbTransaction)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.yapRead { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNotNil(messageDecryptJobFinder.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([messageDecryptData1, messageDecryptData2 ], messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            XCTAssertNotNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId ], sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.contactThreadId })
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNotNil(messageDecryptJobFinder.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(2, messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            XCTAssertEqual([messageDecryptData1, messageDecryptData2 ], messageDecryptJobFinder.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            XCTAssertNotNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(2, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId ], sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).compactMap { $0.contactThreadId })
        }
    }
}
