//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest
@testable import SignalServiceKit

import typealias SignalServiceKit.Attachment

class AttachmentBackfillManagerTest: SSKBaseTest {
    private var attachmentStore: AttachmentStore!
    private var db: InMemoryDB!
    private var interactionStore: InteractionStoreImpl!
    private var mockSyncMessageSender: MockSyncMessageSender!
    private var mockUploadManager: MockAttachmentUploadManager!
    private var recipientDatabaseTable: RecipientDatabaseTable!
    private var threadStore: ThreadStoreImpl!

    private var manager: AttachmentBackfillManager!

    private var localIdentifiers: LocalIdentifiers!
    private var localThread: TSContactThread!
    private var otherAci: Aci!
    private var otherAciThread: TSContactThread!

    override func setUp() {
        super.setUp()

        attachmentStore = AttachmentStore()
        db = InMemoryDB()
        interactionStore = InteractionStoreImpl()
        mockSyncMessageSender = MockSyncMessageSender()
        mockUploadManager = MockAttachmentUploadManager()
        recipientDatabaseTable = RecipientDatabaseTable()
        threadStore = ThreadStoreImpl()

        manager = AttachmentBackfillManager(
            attachmentStore: attachmentStore,
            attachmentUploadManager: mockUploadManager,
            db: db,
            interactionStore: interactionStore,
            recipientDatabaseTable: recipientDatabaseTable,
            syncMessageSender: mockSyncMessageSender,
            threadStore: threadStore,
        )

        localIdentifiers = .forUnitTests
        localThread = TSContactThread(contactUUID: localIdentifiers.aci.serviceIdUppercaseString, contactPhoneNumber: nil)
        otherAci = Aci.randomForTesting()
        otherAciThread = TSContactThread(contactUUID: otherAci.serviceIdUppercaseString, contactPhoneNumber: nil)

        db.write { tx in
            try! localThread.insert(tx.database)
            try! otherAciThread.insert(tx.database)

            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl)
                .registerForTests(
                    localIdentifiers: localIdentifiers,
                    tx: tx,
                )
        }
    }

    // MARK: - handleAttachmentBackfillInboundRequest

    func testEnqueue_dropsRequestIfNotPrimary() {
        let registeredState = try! RegisteredState(
            registrationState: .provisioned,
            localIdentifiers: localIdentifiers,
        )

        let requestProto = buildBackfillRequestProto(
            authorAci: otherAci,
            sentTimestamp: 1234,
            conversationServiceId: otherAci,
        )

        db.write { tx in
            manager.enqueueInboundRequest(
                attachmentBackfillRequestProto: requestProto,
                registeredState: registeredState,
                tx: tx,
            )
        }

        XCTAssertTrue(mockSyncMessageSender.sentResponses.isEmpty)
        db.read { tx in
            XCTAssertEqual(try! AttachmentBackfillInboundRequestRecord.fetchCount(tx.database), 0)
        }
    }

    func testEnqueue_sendsMessageNotFoundWhenTargetMissing() {
        let registeredState = try! RegisteredState(
            registrationState: .registered,
            localIdentifiers: localIdentifiers,
        )

        let requestProto = buildBackfillRequestProto(
            authorAci: otherAci,
            sentTimestamp: 1234,
            conversationServiceId: otherAci,
        )

        db.write { tx in
            manager.enqueueInboundRequest(
                attachmentBackfillRequestProto: requestProto,
                registeredState: registeredState,
                tx: tx,
            )
        }

        XCTAssertEqual(mockSyncMessageSender.sentResponses.count, 1)
        XCTAssertEqual(mockSyncMessageSender.sentResponses[0].error, .messageNotFound)
    }

    // MARK: - processAttachmentBackfillInboundRequest

    func testProcess_emptyAttachments() async throws {
        let (requestRecord, _) = insertMessageAndRequestRecord(thread: otherAciThread)

        let task = manager.processInboundRequest(
            requestRecordId: requestRecord.id,
            localIdentifiers: localIdentifiers,
        )
        try await task.value

        XCTAssertEqual(mockSyncMessageSender.sentResponses.count, 1)
        XCTAssertNil(mockSyncMessageSender.sentResponses[0].error)
        XCTAssertTrue(mockSyncMessageSender.sentResponses[0].attachments!.attachments.isEmpty)
        db.read { tx in
            XCTAssertEqual(try! AttachmentBackfillInboundRequestRecord.fetchCount(tx.database), 0)
        }
    }

    func testProcess_mixedAttachmentResults() async throws {
        let (requestRecord, message) = insertMessageAndRequestRecord(thread: otherAciThread)
        let messageRowId = message.sqliteRowId!
        let threadRowId = otherAciThread.sqliteRowId!

        let attachment1 = insertAttachmentWithReference(messageRowId: messageRowId, threadRowId: threadRowId, orderInMessage: 0)
        let attachment2 = insertAttachmentWithReference(messageRowId: messageRowId, threadRowId: threadRowId, orderInMessage: 1)
        let attachment3 = insertAttachmentWithReference(messageRowId: messageRowId, threadRowId: threadRowId, orderInMessage: 2)
        mockUploadManager.uploadBlock = { attachmentId in
            switch attachmentId {
            case attachment1.id:
                break
            case attachment2.id:
                throw OWSRetryableError()
            case attachment3.id:
                throw OWSGenericError("")
            default:
                XCTFail("Unexpected attachment ID: \(attachmentId)")
            }
        }

        let task = manager.processInboundRequest(
            requestRecordId: requestRecord.id,
            localIdentifiers: localIdentifiers,
        )
        try await task.value

        XCTAssertEqual(mockSyncMessageSender.sentResponses.count, 1)
        let attachmentDatas = mockSyncMessageSender.sentResponses[0].attachments!.attachments
        XCTAssertEqual(attachmentDatas.count, 3)
        XCTAssertNotNil(attachmentDatas[0].attachment)
        XCTAssertEqual(attachmentDatas[1].status, .pending)
        XCTAssertEqual(attachmentDatas[2].status, .terminalError)
        db.read { tx in
            XCTAssertEqual(try! AttachmentBackfillInboundRequestRecord.fetchCount(tx.database), 0)
        }
    }

    func testProcess_allAttachmentsSucceed_distinctProtos() async throws {
        let (requestRecord, message) = insertMessageAndRequestRecord(thread: otherAciThread)
        let messageRowId = message.sqliteRowId!
        let threadRowId = otherAciThread.sqliteRowId!

        let attachment1 = insertAttachmentWithReference(messageRowId: messageRowId, threadRowId: threadRowId, orderInMessage: 0)
        let attachment2 = insertAttachmentWithReference(messageRowId: messageRowId, threadRowId: threadRowId, orderInMessage: 1)
        let attachment3 = insertAttachmentWithReference(messageRowId: messageRowId, threadRowId: threadRowId, orderInMessage: 2)
        mockUploadManager.uploadBlock = { _ in }

        // Read back the CDN keys so we know what to expect.
        let expectedCdnKeys: [String] = [attachment1, attachment2, attachment3].map {
            $0.latestTransitTierInfo!.cdnKey
        }

        let task = manager.processInboundRequest(
            requestRecordId: requestRecord.id,
            localIdentifiers: localIdentifiers,
        )
        try await task.value

        XCTAssertEqual(mockSyncMessageSender.sentResponses.count, 1)
        let attachmentDatas = mockSyncMessageSender.sentResponses[0].attachments!.attachments
        XCTAssertEqual(attachmentDatas.count, 3)

        // Each proto should have a distinct CDN key matching its attachment.
        let protoCdnKeys = attachmentDatas.map { $0.attachment!.cdnKey! }
        XCTAssertEqual(protoCdnKeys[0], expectedCdnKeys[0])
        XCTAssertEqual(protoCdnKeys[1], expectedCdnKeys[1])
        XCTAssertEqual(protoCdnKeys[2], expectedCdnKeys[2])
    }

    func testProcess_stickerAttachment() async throws {
        let (requestRecord, message) = insertMessageAndRequestRecord(thread: otherAciThread)
        let messageRowId = message.sqliteRowId!
        let threadRowId = otherAciThread.sqliteRowId!

        let stickerAttachmentId = insertStickerAttachmentWithReference(
            messageRowId: messageRowId,
            threadRowId: threadRowId,
        )
        mockUploadManager.uploadBlock = { attachmentId in
            XCTAssertEqual(attachmentId, stickerAttachmentId)
        }

        let task = manager.processInboundRequest(
            requestRecordId: requestRecord.id,
            localIdentifiers: localIdentifiers,
        )
        try await task.value

        XCTAssertEqual(mockSyncMessageSender.sentResponses.count, 1)
        let attachmentDatas = mockSyncMessageSender.sentResponses[0].attachments!.attachments
        XCTAssertEqual(attachmentDatas.count, 1)
        XCTAssertNotNil(attachmentDatas[0].attachment)
        db.read { tx in
            XCTAssertEqual(try! AttachmentBackfillInboundRequestRecord.fetchCount(tx.database), 0)
        }
    }

    // MARK: -

    private func buildBackfillRequestProto(
        authorAci: Aci,
        sentTimestamp: UInt64,
        conversationServiceId: ServiceId,
    ) -> SSKProtoSyncMessageAttachmentBackfillRequest {
        let addressableMessage = AddressableMessage(
            author: .aci(authorAci),
            sentTimestamp: sentTimestamp,
        )
        let conversationIdentifier = ConversationIdentifier.serviceId(conversationServiceId)

        let builder = SSKProtoSyncMessageAttachmentBackfillRequest.builder()
        builder.setTargetMessage(addressableMessage.asProto)
        builder.setTargetConversation(conversationIdentifier.asProto)
        return builder.buildInfallibly()
    }

    @discardableResult
    private func insertMessageAndRequestRecord(thread: TSContactThread) -> (AttachmentBackfillInboundRequestRecord, TSOutgoingMessage) {
        return db.write { tx in
            let message = TSOutgoingMessage(
                outgoingMessageWith: .withDefaultValues(
                    thread: thread,
                    timestamp: 1234,
                    messageBody: nil,
                ),
                recipientAddressStates: [:],
            )
            try! message.asRecord().insert(tx.database)

            let record = AttachmentBackfillInboundRequestRecord.fetchOrInsertRecord(
                interactionId: message.sqliteRowId!,
                tx: tx,
            )

            return (record, message)
        }
    }

    private func insertAttachmentWithReference(
        messageRowId: Int64,
        threadRowId: Int64,
        orderInMessage: UInt32,
    ) -> Attachment {
        return db.write { tx in
            var attachmentRecord = Attachment.Record.mockPointer()
            let referenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                messageRowId: messageRowId,
                threadRowId: threadRowId,
                orderInMessage: orderInMessage,
            )

            let attachment = try! attachmentStore.insert(
                &attachmentRecord,
                reference: referenceParams,
                tx: tx,
            )
            return attachment
        }
    }

    @discardableResult
    private func insertStickerAttachmentWithReference(
        messageRowId: Int64,
        threadRowId: Int64,
    ) -> Attachment.IDType {
        return db.write { tx in
            var attachmentRecord = Attachment.Record.mockPointer()
            let referenceParams = AttachmentReference.ConstructionParams.mockMessageStickerReference(
                messageRowId: messageRowId,
                threadRowId: threadRowId,
            )

            let attachment = try! attachmentStore.insert(
                &attachmentRecord,
                reference: referenceParams,
                tx: tx,
            )
            return attachment.id
        }
    }
}

// MARK: -

private class MockAttachmentUploadManager: AttachmentUploadManager {
    var uploadBlock: ((Attachment.IDType) async throws -> Void)?

    func uploadTransitTierAttachment(attachmentId: Attachment.IDType, progress: OWSProgressSink?) async throws {
        try await uploadBlock?(attachmentId)
    }

    func uploadBackup(localUploadMetadata: Upload.EncryptedBackupUploadMetadata, form: Upload.Form, progress: (any OWSProgressSink)?) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        fatalError()
    }

    func uploadTransientAttachment(dataSource: DataSourcePath, progress: (any OWSProgressSink)?) async throws -> Upload.Result<Upload.LocalUploadMetadata> {
        fatalError()
    }

    func uploadLinkNSyncAttachment(dataSource: DataSourcePath, progress: (any OWSProgressSink)?) async throws -> Upload.Result<Upload.LinkNSyncUploadMetadata> {
        fatalError()
    }

    func uploadMediaTierAttachment(attachmentId: Attachment.IDType, uploadEra: String, localAci: LibSignalClient.Aci, backupKey: MediaRootBackupKey, auth: BackupServiceAuth, progress: (any OWSProgressSink)?) async throws {
        fatalError()
    }

    func uploadMediaTierThumbnailAttachment(attachmentId: Attachment.IDType, uploadEra: String, localAci: LibSignalClient.Aci, backupKey: MediaRootBackupKey, auth: BackupServiceAuth, progress: (any OWSProgressSink)?) async throws {
        fatalError()
    }
}

// MARK: -

private class MockSyncMessageSender: AttachmentBackfillManager.AttachmentBackfillSyncMessageSender {
    var sentResponses = [SSKProtoSyncMessageAttachmentBackfillResponse]()

    func add(attachmentBackfillResponseSyncMessage: AttachmentBackfillResponseSyncMessage, tx: DBWriteTransaction) {
        sentResponses.append(attachmentBackfillResponseSyncMessage.responseProto)
    }

    func add(attachmentBackfillRequestSyncMessage: AttachmentBackfillRequestSyncMessage, tx: DBWriteTransaction) {
        // Do nothing
    }
}
