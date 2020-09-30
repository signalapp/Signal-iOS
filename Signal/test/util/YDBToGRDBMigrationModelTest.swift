//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit
@testable import Signal
@testable import SignalMessaging

extension AnyThreadFinder {
    func visibleThreadUniqueIds(isArchived: Bool, transaction: SDSAnyReadTransaction) throws -> [String] {
        var result = [String]()
        try enumerateVisibleThreads(isArchived: isArchived, transaction: transaction) { thread in
            result.append(thread.uniqueId)
        }
        return result
    }
}

extension InteractionFinder {
    func allInteractionIds(transaction: SDSAnyReadTransaction) throws -> [String] {
        var result = [String]()
        try enumerateInteractionIds(transaction: transaction) { (uniqueId, _) in
            result.append(uniqueId)
        }
        return result
    }
}

class YDBToGRDBMigrationModelTest: SignalBaseTest {

    // MARK: - Dependencies

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    // MARK: -

    override func setUp() {
        super.setUp()

        // ensure local client has necessary "registered" state
        let localE164Identifier = "+13235551234"
        let localUUID = UUID()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)
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

    func testSignalRecipient() {
        storageCoordinator.useGRDBForTests()

        let uuid1 = UUID()
        let uuid2 = UUID()
        let uuid3 = UUID()
        let uuid4 = UUID()
        let uuid5 = UUID()
        let uuid6 = UUID()
        let phoneNumber1 = "+13213214321"
        let phoneNumber2 = "+13213214322"
        let phoneNumber3 = "+13213214323"
        let phoneNumber4 = "+13213214324"
        let phoneNumber5 = "+13213214325"
        let phoneNumber6 = "+13213214326"
        let phoneNumber7 = "+13213214327"
        let deviceId0 = NSNumber(value: OWSDevicePrimaryDeviceId)
        let deviceId1 = NSNumber(value: OWSDevicePrimaryDeviceId + 1)
        let deviceId2 = NSNumber(value: OWSDevicePrimaryDeviceId + 2)
        let model1 = SignalRecipient(phoneNumber: phoneNumber1, uuid: uuid1, devices: [deviceId0])
        let model2 = SignalRecipient(phoneNumber: phoneNumber2, uuid: uuid2, devices: [deviceId0, deviceId1])
        let model3 = SignalRecipient(phoneNumber: phoneNumber3, uuid: uuid3, devices: [deviceId0, deviceId1, deviceId2])
        // Duplicate uuid. One recipient should be discarded.
        let model4a = SignalRecipient(phoneNumber: phoneNumber4, uuid: uuid4, devices: [deviceId0])
        let model4b = SignalRecipient(phoneNumber: phoneNumber5, uuid: uuid4, devices: [deviceId0])
        // Duplicate phone, unique uuid. One recipient should lose its phone number.
        let model5a = SignalRecipient(phoneNumber: phoneNumber6, uuid: uuid5, devices: [deviceId0])
        let model5b = SignalRecipient(phoneNumber: phoneNumber6, uuid: uuid6, devices: [deviceId0])
        // Duplicate phone, no uuid. One recipient should be discarded.
        let model6a = SignalRecipient(phoneNumber: phoneNumber7, uuid: nil, devices: [deviceId0])
        let model6b = SignalRecipient(phoneNumber: phoneNumber7, uuid: nil, devices: [deviceId0])

        self.yapRead { transaction in
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model1.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model2.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model3.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model4a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model4b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model5a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model5b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model6a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model6b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertEqual(0, SignalRecipient.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model1.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model2.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model3.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model4a.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model4b.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model5a.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model5b.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model6a.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model6b.uniqueId, transaction: transaction))
            XCTAssertEqual(0, SignalRecipient.anyCount(transaction: transaction))
        }

        self.yapWrite { transaction in
            model1.anyInsert(transaction: transaction.asAnyWrite)
            model2.anyInsert(transaction: transaction.asAnyWrite)
            // Don't insert 3.
            model4a.anyInsert(transaction: transaction.asAnyWrite)
            model4b.anyInsert(transaction: transaction.asAnyWrite)
            model5a.anyInsert(transaction: transaction.asAnyWrite)
            model5b.anyInsert(transaction: transaction.asAnyWrite)
            model6a.anyInsert(transaction: transaction.asAnyWrite)
            model6b.anyInsert(transaction: transaction.asAnyWrite)
        }

        self.yapRead { transaction in
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model1.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model2.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model3.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model4a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model4b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model5a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model5b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model6a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model6b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertEqual(8, SignalRecipient.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model1.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model2.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model3.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model4a.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model4b.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model5a.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model5b.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model6a.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model6b.uniqueId, transaction: transaction))
            XCTAssertEqual(0, SignalRecipient.anyCount(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBUnorderedRecordMigrator<SignalRecipient>(label: "SignalRecipient", ydbTransaction: ydbTransaction)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.yapRead { transaction in
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model1.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model2.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model3.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model4a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model4b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model5a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model5b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model6a.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model6b.uniqueId, transaction: transaction.asAnyRead))
            XCTAssertEqual(8, SignalRecipient.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model1.uniqueId, transaction: transaction))
            XCTAssertNotNil(SignalRecipient.anyFetch(uniqueId: model2.uniqueId, transaction: transaction))
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: model3.uniqueId, transaction: transaction))

            // Exactly one should be migrated and one discarded.
            let model4aCopy: SignalRecipient? = SignalRecipient.anyFetch(uniqueId: model4a.uniqueId, transaction: transaction)
            let model4bCopy: SignalRecipient? = SignalRecipient.anyFetch(uniqueId: model4b.uniqueId, transaction: transaction)
            XCTAssertTrue(model4aCopy == nil || model4bCopy == nil)
            XCTAssertTrue(model4aCopy != nil || model4bCopy != nil)

            // Both should be migrated; one will no longer have a phone number.
            let model5aCopy: SignalRecipient? = SignalRecipient.anyFetch(uniqueId: model5a.uniqueId, transaction: transaction)
            let model5bCopy: SignalRecipient? = SignalRecipient.anyFetch(uniqueId: model5b.uniqueId, transaction: transaction)
            XCTAssertNotNil(model5aCopy)
            XCTAssertNotNil(model5bCopy)
            XCTAssertTrue(model5aCopy?.recipientPhoneNumber == nil || model5bCopy?.recipientPhoneNumber == nil)
            XCTAssertTrue(model5aCopy?.recipientPhoneNumber != nil || model5bCopy?.recipientPhoneNumber != nil)

            // Exactly one should be migrated and one discarded.
            let model6aCopy: SignalRecipient? = SignalRecipient.anyFetch(uniqueId: model6a.uniqueId, transaction: transaction)
            let model6bCopy: SignalRecipient? = SignalRecipient.anyFetch(uniqueId: model6b.uniqueId, transaction: transaction)
            XCTAssertTrue(model6aCopy == nil || model6bCopy == nil)
            XCTAssertTrue(model6aCopy != nil || model6bCopy != nil)

            XCTAssertEqual(6, SignalRecipient.anyCount(transaction: transaction))
        }
    }

    func randomKnownStickerPack() -> KnownStickerPack {
        return KnownStickerPack(info: randomStickerPackInfo())
    }

    func testKnownStickerPack() {
        storageCoordinator.useGRDBForTests()

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
                    GRDBUnorderedRecordMigrator<KnownStickerPack>(label: "KnownStickerPack", ydbTransaction: ydbTransaction)
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
        storageCoordinator.useGRDBForTests()

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
            //
            // NOTE: We don't need to verify that GRDB contains no
            //       OWSMessageDecryptJobs; the table doesn't even exist.
        }

        self.yapWrite { transaction in
            // SSKMessageDecryptJobRecord
            messageDecryptJobQueue.add(envelopeData: messageDecryptData1,
                                       serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                       transaction: transaction.asAnyWrite)
            messageDecryptJobQueue.add(envelopeData: messageDecryptData2,
                                       serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                       transaction: transaction.asAnyWrite)
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
            messageDecryptJobFinder2.addJob(forEnvelopeData: messageDecryptData3,
                                            serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                            transaction: transaction.asAnyWrite)
            messageDecryptJobFinder2.addJob(forEnvelopeData: messageDecryptData4,
                                            serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                            transaction: transaction.asAnyWrite)
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
            //
            // NOTE: We don't need to verify that GRDB contains no
            //       OWSMessageDecryptJobs; the table doesn't even exist.
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
            //
            // NOTE: We don't need to verify that GRDB contains no
            //       OWSMessageDecryptJobs; the table doesn't even exist.
        }
    }

    func testDecryptJobs() {
        storageCoordinator.useGRDBForTests()

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
            //
            // NOTE: We don't need to verify that GRDB contains no
            //       OWSMessageDecryptJobs; the table doesn't even exist.
        }

        self.yapWrite { transaction in
            // SSKMessageDecryptJobRecord
            messageDecryptJobQueue.add(envelopeData: messageDecryptData1,
                                       serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                       transaction: transaction.asAnyWrite)
            messageDecryptJobQueue.add(envelopeData: messageDecryptData2,
                                       serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                       transaction: transaction.asAnyWrite)
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
            messageDecryptJobFinder2.addJob(forEnvelopeData: messageDecryptData3,
                                            serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                            transaction: transaction.asAnyWrite)
            messageDecryptJobFinder2.addJob(forEnvelopeData: messageDecryptData4,
                                            serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                            transaction: transaction.asAnyWrite)
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
            //
            // NOTE: We don't need to verify that GRDB contains no
            //       OWSMessageDecryptJobs; the table doesn't even exist.
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
            //
            // NOTE: We don't need to verify that GRDB contains no
            //       OWSMessageDecryptJobs; the table doesn't even exist.
        }
    }

    func testInteractions() {
        storageCoordinator.useGRDBForTests()

        // Threads
        let contactThread1 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334444"))
        let contactThread2 = TSContactThread(contactAddress: SignalServiceAddress(phoneNumber: "+13213334445"))
        // Attachments
        let attachmentData1 = Randomness.generateRandomBytes(1024)
        let attachment1 = TSAttachmentStream(contentType: OWSMimeTypeImageGif,
                                             byteCount: UInt32(attachmentData1.count),
                                             sourceFilename: "some.gif", caption: nil, albumMessageId: nil)
        let attachmentData2 = Randomness.generateRandomBytes(2048)
        let attachment2 = TSAttachmentStream(contentType: OWSMimeTypePdf,
                                             byteCount: UInt32(attachmentData2.count),
                                             sourceFilename: "some.df", caption: nil, albumMessageId: nil)
        // Messages
        let outgoingMessage1 = TSOutgoingMessage(in: contactThread1, messageBody: "good heavens", attachmentId: attachment1.uniqueId)
        let outgoingMessage2 = TSOutgoingMessage(in: contactThread2, messageBody: "land's sakes", attachmentId: attachment2.uniqueId)
        let outgoingMessage3 = TSOutgoingMessage(in: contactThread2, messageBody: "oh my word", attachmentId: nil)

        self.yapRead { transaction in
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual(0, TSInteraction.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSInteraction.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction))
        }

        self.yapWrite { transaction in
            // Threads
            contactThread1.anyInsert(transaction: transaction.asAnyWrite)
            contactThread2.anyInsert(transaction: transaction.asAnyWrite)
            // Attachments
            attachment1.anyInsert(transaction: transaction.asAnyWrite)
            attachment2.anyInsert(transaction: transaction.asAnyWrite)
            // Messages
            outgoingMessage1.anyInsert(transaction: transaction.asAnyWrite)
            outgoingMessage2.anyInsert(transaction: transaction.asAnyWrite)
            outgoingMessage3.anyInsert(transaction: transaction.asAnyWrite)
        }

        self.yapRead { transaction in
            XCTAssertEqual(2, TSThread.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId].sorted(), TSThread.anyAllUniqueIds(transaction: transaction.asAnyRead).sorted())
            XCTAssertEqual(3, TSInteraction.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual([outgoingMessage1.uniqueId, outgoingMessage2.uniqueId, outgoingMessage3.uniqueId].sorted(), TSInteraction.anyAllUniqueIds(transaction: transaction.asAnyRead).sorted())
            XCTAssertEqual([outgoingMessage1, outgoingMessage2, outgoingMessage3].compactMap { $0.body }.sorted(), TSInteraction.anyFetchAll(transaction: transaction.asAnyRead).compactMap { ($0 as! TSMessage).body }.sorted())
            XCTAssertEqual(2, TSAttachment.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual([attachment1.uniqueId, attachment2.uniqueId].sorted(), TSAttachment.anyAllUniqueIds(transaction: transaction.asAnyRead).sorted())
        }
        self.read { transaction in
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSInteraction.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBUnorderedRecordMigrator<TSAttachment>(label: "attachments", ydbTransaction: ydbTransaction),
                    GRDBUnorderedRecordMigrator<TSThread>(label: "threads", ydbTransaction: ydbTransaction)
                ]
            },
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBInteractionMigrator(ydbTransaction: ydbTransaction)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.yapRead { transaction in
            XCTAssertEqual(2, TSThread.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId].sorted(), TSThread.anyAllUniqueIds(transaction: transaction.asAnyRead).sorted())
            XCTAssertEqual(3, TSInteraction.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual([outgoingMessage1.uniqueId, outgoingMessage2.uniqueId, outgoingMessage3.uniqueId].sorted(), TSInteraction.anyAllUniqueIds(transaction: transaction.asAnyRead).sorted())
            XCTAssertEqual([outgoingMessage1, outgoingMessage2, outgoingMessage3].compactMap { $0.body }.sorted(), TSInteraction.anyFetchAll(transaction: transaction.asAnyRead).compactMap { ($0 as! TSMessage).body }.sorted())
            XCTAssertEqual(2, TSAttachment.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual([attachment1.uniqueId, attachment2.uniqueId].sorted(), TSAttachment.anyAllUniqueIds(transaction: transaction.asAnyRead).sorted())
        }
        self.read { transaction in
            XCTAssertEqual(2, TSThread.anyCount(transaction: transaction))
            XCTAssertEqual([contactThread1.uniqueId, contactThread2.uniqueId].sorted(), TSThread.anyAllUniqueIds(transaction: transaction).sorted())
            XCTAssertEqual(3, TSInteraction.anyCount(transaction: transaction))
            XCTAssertEqual([outgoingMessage1.uniqueId, outgoingMessage2.uniqueId, outgoingMessage3.uniqueId].sorted(), TSInteraction.anyAllUniqueIds(transaction: transaction).sorted())
            XCTAssertEqual([outgoingMessage1, outgoingMessage2, outgoingMessage3].compactMap { $0.body }.sorted(), TSInteraction.anyFetchAll(transaction: transaction).compactMap { ($0 as! TSMessage).body }.sorted())
            XCTAssertEqual(2, TSAttachment.anyCount(transaction: transaction))
            XCTAssertEqual([attachment1.uniqueId, attachment2.uniqueId].sorted(), TSAttachment.anyAllUniqueIds(transaction: transaction).sorted())
        }
    }

    func testThreadAndInteractionOrdering() {
        storageCoordinator.useGRDBForTests()

        self.yapRead { transaction in
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual(0, TSInteraction.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSInteraction.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction))
        }

        // Threads
        let contactThreadFactory = ContactThreadFactory()
        let groupThreadFactory = GroupThreadFactory()
        var thread1: TSThread!
        var thread2: TSThread!
        var thread3: TSThread!
        var thread4: TSThread!

        var message1: TSInteraction!
        var message2: TSInteraction!
        var message3: TSInteraction!
        var message4: TSInteraction!
        var message5: TSInteraction!
        var message6: TSInteraction!
        var message7: TSInteraction!
        var message8: TSInteraction!
        self.yapWrite { transaction in
            thread1 = contactThreadFactory.create(transaction: transaction.asAnyWrite)
            thread2 = groupThreadFactory.create(transaction: transaction.asAnyWrite)
            thread3 = contactThreadFactory.create(transaction: transaction.asAnyWrite)
            thread4 = groupThreadFactory.create(transaction: transaction.asAnyWrite)

            // There should be 2 "group update" info messages.
            XCTAssertEqual(2, TSInteraction.anyCount(transaction: transaction.asAnyRead))
            // For simplicity, remove the "group update" info messages.
            do {
                let interactions = TSInteraction.anyFetchAll(transaction: transaction.asAnyRead)
                for interaction in interactions {
                    interaction.anyRemove(transaction: transaction.asAnyWrite)
                }
            }

            let messageFactory = IncomingMessageFactory()

            // We deliberately interleave message order across different
            // threads.

            messageFactory.threadCreator = { _ in return thread1 }
            message1 = messageFactory.create(transaction: transaction.asAnyWrite)

            messageFactory.threadCreator = { _ in return thread2 }
            message2 = messageFactory.create(transaction: transaction.asAnyWrite)

            messageFactory.threadCreator = { _ in return thread3 }
            message3 = messageFactory.create(transaction: transaction.asAnyWrite)

            messageFactory.threadCreator = { _ in return thread4 }
            message4 = messageFactory.create(transaction: transaction.asAnyWrite)

            messageFactory.threadCreator = { _ in return thread1 }
            message5 = messageFactory.create(transaction: transaction.asAnyWrite)

            messageFactory.threadCreator = { _ in return thread2 }
            message6 = messageFactory.create(transaction: transaction.asAnyWrite)

            messageFactory.threadCreator = { _ in return thread3 }
            message7 = messageFactory.create(transaction: transaction.asAnyWrite)

            messageFactory.threadCreator = { _ in return thread4 }
            message8 = messageFactory.create(transaction: transaction.asAnyWrite)
        }

        self.yapRead { transaction in
            XCTAssertEqual(4, TSThread.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual(8, TSInteraction.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction.asAnyRead))

            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread1.uniqueId).count(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread2.uniqueId).count(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread3.uniqueId).count(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread4.uniqueId).count(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSInteraction.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction))
        }

        let migratorGroups = [
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBUnorderedRecordMigrator<TSAttachment>(label: "attachments", ydbTransaction: ydbTransaction),
                    GRDBUnorderedRecordMigrator<TSThread>(label: "threads", ydbTransaction: ydbTransaction)
                ]
            },
            GRDBMigratorGroup { ydbTransaction in
                return [
                    GRDBInteractionMigrator(ydbTransaction: ydbTransaction)
                ]
            }
        ]

        try! YDBToGRDBMigration().migrate(migratorGroups: migratorGroups)

        self.yapRead { transaction in
            XCTAssertEqual(4, TSThread.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual(8, TSInteraction.anyCount(transaction: transaction.asAnyRead))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction.asAnyRead))

            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread1.uniqueId).count(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread2.uniqueId).count(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread3.uniqueId).count(transaction: transaction.asAnyRead))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread4.uniqueId).count(transaction: transaction.asAnyRead))

            XCTAssertEqual(4, try! AnyThreadFinder().visibleThreadCount(isArchived: false, transaction: transaction.asAnyRead))
            XCTAssertEqual([thread4.uniqueId, thread3.uniqueId, thread2.uniqueId, thread1.uniqueId ], try! AnyThreadFinder().visibleThreadUniqueIds(isArchived: false, transaction: transaction.asAnyRead))
            XCTAssertEqual([message5.uniqueId, message1.uniqueId ], try! InteractionFinder(threadUniqueId: thread1.uniqueId).allInteractionIds(transaction: transaction.asAnyRead))
            XCTAssertEqual([message6.uniqueId, message2.uniqueId ], try! InteractionFinder(threadUniqueId: thread2.uniqueId).allInteractionIds(transaction: transaction.asAnyRead))
            XCTAssertEqual([message7.uniqueId, message3.uniqueId ], try! InteractionFinder(threadUniqueId: thread3.uniqueId).allInteractionIds(transaction: transaction.asAnyRead))
            XCTAssertEqual([message8.uniqueId, message4.uniqueId ], try! InteractionFinder(threadUniqueId: thread4.uniqueId).allInteractionIds(transaction: transaction.asAnyRead))
        }
        self.read { transaction in
            XCTAssertEqual(4, TSThread.anyCount(transaction: transaction))
            XCTAssertEqual(8, TSInteraction.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSAttachment.anyCount(transaction: transaction))

            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread1.uniqueId).count(transaction: transaction))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread2.uniqueId).count(transaction: transaction))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread3.uniqueId).count(transaction: transaction))
            XCTAssertEqual(2, InteractionFinder(threadUniqueId: thread4.uniqueId).count(transaction: transaction))

            XCTAssertEqual(4, try! AnyThreadFinder().visibleThreadCount(isArchived: false, transaction: transaction))
            XCTAssertEqual([thread4.uniqueId, thread3.uniqueId, thread2.uniqueId, thread1.uniqueId ], try! AnyThreadFinder().visibleThreadUniqueIds(isArchived: false, transaction: transaction))
            XCTAssertEqual([message5.uniqueId, message1.uniqueId ], try! InteractionFinder(threadUniqueId: thread1.uniqueId).allInteractionIds(transaction: transaction))
            XCTAssertEqual([message6.uniqueId, message2.uniqueId ], try! InteractionFinder(threadUniqueId: thread2.uniqueId).allInteractionIds(transaction: transaction))
            XCTAssertEqual([message7.uniqueId, message3.uniqueId ], try! InteractionFinder(threadUniqueId: thread3.uniqueId).allInteractionIds(transaction: transaction))
            XCTAssertEqual([message8.uniqueId, message4.uniqueId ], try! InteractionFinder(threadUniqueId: thread4.uniqueId).allInteractionIds(transaction: transaction))
        }
    }
}
