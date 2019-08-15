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
        // SSKMessageSenderJobRecord
        let outgoingMessage1 = TSOutgoingMessage(in: contactThread1, messageBody: "good heavens", attachmentId: nil)
        let outgoingMessage2 = TSOutgoingMessage(in: contactThread1, messageBody: "land's sakes", attachmentId: nil)
        let outgoingMessage3 = TSOutgoingMessage(in: contactThread2, messageBody: "oh my word", attachmentId: nil)
        // OWSMessageDecryptJob
        let messageDecryptData3 = Randomness.generateRandomBytes(1024)
        let messageDecryptData4 = Randomness.generateRandomBytes(1024)

        // SSKMessageDecryptJobRecord
        let messageDecryptJobFinder1 = AnyJobRecordFinder<SSKMessageDecryptJobRecord>()
        let messageDecryptJobQueue = SSKMessageDecryptJobQueue()
        // OWSSessionResetJobRecord
        let sessionResetJobFinder = AnyJobRecordFinder<OWSSessionResetJobRecord>()
        let sessionResetJobQueue = SessionResetJobQueue()
        // SSKMessageSenderJobRecord
        let messageSenderJobFinder = AnyJobRecordFinder<SSKMessageSenderJobRecord>()
        let messageSenderJobQueue = MessageSenderJobQueue()
        // OWSMessageDecryptJob
        let messageDecryptJobFinder2 = OWSMessageDecryptJobFinder()

        self.yapRead { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            // SSKMessageSenderJobRecord
            XCTAssertNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            // OWSMessageDecryptJob
            XCTAssertNil(messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead))
            XCTAssertEqual(0, messageDecryptJobFinder2.queuedJobCount(with: transaction.asAnyRead))
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // SSKMessageSenderJobRecord
            XCTAssertNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSMessageDecryptJob
            XCTAssertNil(messageDecryptJobFinder2.nextJob(transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder2.queuedJobCount(with: transaction))
        }

        self.yapWrite { transaction in
            // SSKMessageDecryptJobRecord
            messageDecryptJobQueue.add(envelopeData: messageDecryptData1, transaction: transaction.asAnyWrite)
            messageDecryptJobQueue.add(envelopeData: messageDecryptData2, transaction: transaction.asAnyWrite)
            // OWSSessionResetJobRecord
            sessionResetJobQueue.add(contactThread: contactThread1, transaction: transaction.asAnyWrite)
            sessionResetJobQueue.add(contactThread: contactThread2, transaction: transaction.asAnyWrite)
            // SSKMessageSenderJobRecord
            contactThread1.anyInsert(transaction: transaction.asAnyWrite)
            contactThread2.anyInsert(transaction: transaction.asAnyWrite)
            outgoingMessage1.anyInsert(transaction: transaction.asAnyWrite)
            outgoingMessage2.anyInsert(transaction: transaction.asAnyWrite)
            outgoingMessage3.anyInsert(transaction: transaction.asAnyWrite)
            messageSenderJobQueue.add(message: outgoingMessage1.asPreparer, transaction: transaction.asAnyWrite)
            messageSenderJobQueue.add(message: outgoingMessage2.asPreparer, transaction: transaction.asAnyWrite)
            messageSenderJobQueue.add(message: outgoingMessage3.asPreparer, transaction: transaction.asAnyWrite)
            // OWSMessageDecryptJob
            messageDecryptJobFinder2.addJob(forEnvelopeData: messageDecryptData3, transaction: transaction.asAnyWrite)
            messageDecryptJobFinder2.addJob(forEnvelopeData: messageDecryptData4, transaction: transaction.asAnyWrite)
        }

        self.yapRead { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNotNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([messageDecryptData1, messageDecryptData2 ], messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            XCTAssertNotNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId ], sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.contactThreadId })
            // SSKMessageSenderJobRecord
            XCTAssertNotNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(3, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([outgoingMessage1.uniqueId, outgoingMessage2.uniqueId, outgoingMessage3.uniqueId ], messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.messageId })
            // OWSMessageDecryptJob
            XCTAssertNotNil(messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder2.queuedJobCount(with: transaction.asAnyRead))
            XCTAssertEqual(messageDecryptData3, messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead)!.envelopeData)
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // SSKMessageSenderJobRecord
            XCTAssertNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSMessageDecryptJob
            XCTAssertNil(messageDecryptJobFinder2.nextJob(transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder2.queuedJobCount(with: transaction))
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
            XCTAssertNotNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([messageDecryptData1, messageDecryptData2 ], messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            XCTAssertNotNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId ], sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.contactThreadId })
            // SSKMessageSenderJobRecord
            XCTAssertNotNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(3, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([outgoingMessage1.uniqueId, outgoingMessage2.uniqueId, outgoingMessage3.uniqueId ], messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.messageId })
            // OWSMessageDecryptJob
            XCTAssertNotNil(messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder2.queuedJobCount(with: transaction.asAnyRead))
            XCTAssertEqual(messageDecryptData3, messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead)!.envelopeData)
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNotNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(2, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            XCTAssertEqual([messageDecryptData1, messageDecryptData2 ], messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            XCTAssertNotNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(2, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId ], sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).compactMap { $0.contactThreadId })
            // SSKMessageSenderJobRecord
            XCTAssertNotNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(3, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            XCTAssertEqual([outgoingMessage1.uniqueId, outgoingMessage2.uniqueId, outgoingMessage3.uniqueId ], messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction).compactMap { $0.messageId })
            // OWSMessageDecryptJob
            //
            // NOTE: These jobs are _NOT_ migrated.
            //       See testDecryptJobs() which uses GRDBDecryptJobMigrator.
            XCTAssertNil(messageDecryptJobFinder2.nextJob(transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder2.queuedJobCount(with: transaction))
        }
    }

    func testDecryptJobs() {
        // SSKMessageDecryptJobRecord
        let messageDecryptData1 = Randomness.generateRandomBytes(1024)
        let messageDecryptData2 = Randomness.generateRandomBytes(1024)
        // OWSSessionResetJobRecord
        let contactThread1 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334444"))
        let contactThread2 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334445"))
        // SSKMessageSenderJobRecord
        let outgoingMessage1 = TSOutgoingMessage(in: contactThread1, messageBody: "good heavens", attachmentId: nil)
        let outgoingMessage2 = TSOutgoingMessage(in: contactThread1, messageBody: "land's sakes", attachmentId: nil)
        let outgoingMessage3 = TSOutgoingMessage(in: contactThread2, messageBody: "oh my word", attachmentId: nil)
        // OWSMessageDecryptJob
        let messageDecryptData3 = Randomness.generateRandomBytes(1024)
        let messageDecryptData4 = Randomness.generateRandomBytes(1024)

        // SSKMessageDecryptJobRecord
        let messageDecryptJobFinder1 = AnyJobRecordFinder<SSKMessageDecryptJobRecord>()
        let messageDecryptJobQueue = SSKMessageDecryptJobQueue()
        // OWSSessionResetJobRecord
        let sessionResetJobFinder = AnyJobRecordFinder<OWSSessionResetJobRecord>()
        let sessionResetJobQueue = SessionResetJobQueue()
        // SSKMessageSenderJobRecord
        let messageSenderJobFinder = AnyJobRecordFinder<SSKMessageSenderJobRecord>()
        let messageSenderJobQueue = MessageSenderJobQueue()
        // OWSMessageDecryptJob
        let messageDecryptJobFinder2 = OWSMessageDecryptJobFinder()

        self.yapRead { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            // SSKMessageSenderJobRecord
            XCTAssertNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            // OWSMessageDecryptJob
            XCTAssertNil(messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead))
            XCTAssertEqual(0, messageDecryptJobFinder2.queuedJobCount(with: transaction.asAnyRead))
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // SSKMessageSenderJobRecord
            XCTAssertNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSMessageDecryptJob
            XCTAssertNil(messageDecryptJobFinder2.nextJob(transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder2.queuedJobCount(with: transaction))
        }

        self.yapWrite { transaction in
            // SSKMessageDecryptJobRecord
            messageDecryptJobQueue.add(envelopeData: messageDecryptData1, transaction: transaction.asAnyWrite)
            messageDecryptJobQueue.add(envelopeData: messageDecryptData2, transaction: transaction.asAnyWrite)
            // OWSSessionResetJobRecord
            sessionResetJobQueue.add(contactThread: contactThread1, transaction: transaction.asAnyWrite)
            sessionResetJobQueue.add(contactThread: contactThread2, transaction: transaction.asAnyWrite)
            // SSKMessageSenderJobRecord
            contactThread1.anyInsert(transaction: transaction.asAnyWrite)
            contactThread2.anyInsert(transaction: transaction.asAnyWrite)
            outgoingMessage1.anyInsert(transaction: transaction.asAnyWrite)
            outgoingMessage2.anyInsert(transaction: transaction.asAnyWrite)
            outgoingMessage3.anyInsert(transaction: transaction.asAnyWrite)
            messageSenderJobQueue.add(message: outgoingMessage1.asPreparer, transaction: transaction.asAnyWrite)
            messageSenderJobQueue.add(message: outgoingMessage2.asPreparer, transaction: transaction.asAnyWrite)
            messageSenderJobQueue.add(message: outgoingMessage3.asPreparer, transaction: transaction.asAnyWrite)
            // OWSMessageDecryptJob
            messageDecryptJobFinder2.addJob(forEnvelopeData: messageDecryptData3, transaction: transaction.asAnyWrite)
            messageDecryptJobFinder2.addJob(forEnvelopeData: messageDecryptData4, transaction: transaction.asAnyWrite)
        }

        self.yapRead { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNotNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([messageDecryptData1, messageDecryptData2 ], messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            XCTAssertNotNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId ], sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.contactThreadId })
            // SSKMessageSenderJobRecord
            XCTAssertNotNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(3, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([outgoingMessage1.uniqueId, outgoingMessage2.uniqueId, outgoingMessage3.uniqueId ], messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.messageId })
            // OWSMessageDecryptJob
            XCTAssertNotNil(messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder2.queuedJobCount(with: transaction.asAnyRead))
            XCTAssertEqual(messageDecryptData3, messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead)!.envelopeData)
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSSessionResetJobRecord
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // SSKMessageSenderJobRecord
            XCTAssertNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSMessageDecryptJob
            XCTAssertNil(messageDecryptJobFinder2.nextJob(transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder2.queuedJobCount(with: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBDecryptJobMigrator(ydbTransaction: ydbTransaction)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.yapRead { transaction in
            // SSKMessageDecryptJobRecord
            XCTAssertNotNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([messageDecryptData1, messageDecryptData2 ], messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            XCTAssertNotNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(2, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId ], sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.contactThreadId })
            // SSKMessageSenderJobRecord
            XCTAssertNotNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction.asAnyRead))
            XCTAssertEqual(3, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).count)
            XCTAssertEqual([outgoingMessage1.uniqueId, outgoingMessage2.uniqueId, outgoingMessage3.uniqueId ], messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction.asAnyRead).compactMap { $0.messageId })
            // OWSMessageDecryptJob
            XCTAssertNotNil(messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, messageDecryptJobFinder2.queuedJobCount(with: transaction.asAnyRead))
            XCTAssertEqual(messageDecryptData3, messageDecryptJobFinder2.nextJob(transaction: transaction.asAnyRead)!.envelopeData)
        }
        self.read { transaction in
            // SSKMessageDecryptJobRecord
            //
            // NOTE: These jobs are migrated from OWSMessageDecryptJob.
            XCTAssertNotNil(messageDecryptJobFinder1.getNextReady(label: SSKMessageDecryptJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(2, messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            XCTAssertEqual([messageDecryptData3, messageDecryptData4 ], messageDecryptJobFinder1.allRecords(label: SSKMessageDecryptJobQueue.jobRecordLabel, status: .ready, transaction: transaction).compactMap { $0.envelopeData })
            // OWSSessionResetJobRecord
            //
            // NOTE: These jobs are _NOT_ migrated.
            XCTAssertNil(sessionResetJobFinder.getNextReady(label: sessionResetJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, sessionResetJobFinder.allRecords(label: sessionResetJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // SSKMessageSenderJobRecord
            //
            // NOTE: These jobs are _NOT_ migrated.
            XCTAssertNil(messageSenderJobFinder.getNextReady(label: MessageSenderJobQueue.jobRecordLabel, transaction: transaction))
            XCTAssertEqual(0, messageSenderJobFinder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction).count)
            // OWSMessageDecryptJob
            //
            // NOTE: These jobs are migrated to SSKMessageDecryptJobRecord.
            XCTAssertNil(messageDecryptJobFinder2.nextJob(transaction: transaction))
            XCTAssertEqual(0, messageDecryptJobFinder2.queuedJobCount(with: transaction))
        }
    }
}
