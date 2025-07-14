//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class EditManagerTests: SSKBaseTest {
    var db: (any DB)!
    var authorAci: Aci!
    var thread: TSThread!

    override func setUp() {
        super.setUp()
        db = InMemoryDB()
        authorAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")
        thread = TSThread.init(
            grdbId: 1,
            uniqueId: "1",
            conversationColorNameObsolete: "Obsolete",
            creationDate: nil,
            editTargetTimestamp: nil,
            isArchivedObsolete: false,
            isMarkedUnreadObsolete: false,
            lastDraftInteractionRowId: 0,
            lastDraftUpdateTimestamp: 0,
            lastInteractionRowId: 0,
            lastSentStoryTimestamp: nil,
            lastVisibleSortIdObsolete: 0,
            lastVisibleSortIdOnScreenPercentageObsolete: 0,
            mentionNotificationMode: .always,
            messageDraft: nil,
            messageDraftBodyRanges: nil,
            mutedUntilDateObsolete: nil,
            mutedUntilTimestampObsolete: 0,
            shouldThreadBeVisible: true,
            storyViewMode: .default
        )
    }

    func testBasicValidation() throws {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.messageBody = "BAR"
            builder.authorAci = authorAci
            builder.expireStartedAt = 3
        }

        let editMessage = createEditDataMessage { $0.setBody("FOO") }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editMessageStoreMock = EditMessageStoreMock()
        let editManager = EditManagerImpl(context:
            .init(
                attachmentStore: AttachmentStoreMock(),
                dataStore: dataStoreMock,
                editManagerAttachments: MockEditManagerAttachments(),
                editMessageStore: editMessageStoreMock,
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        try db.write { tx in
            _ = try editManager.processIncomingEditMessage(
                editMessage,
                serverTimestamp: 1,
                serverGuid: UUID().uuidString,
                serverDeliveryTimestamp: 1234,
                thread: thread,
                editTarget: .incomingMessage(IncomingEditMessageWrapper(
                    message: targetMessage,
                    thread: thread,
                    authorAci: authorAci
                )),
                tx: tx
            )

            compare(
                dataStoreMock.editMessageCopy,
                targetMessage,
                propertyList: editPropertyList
            )

            compare(
                dataStoreMock.oldMessageCopy,
                targetMessage,
                propertyList: originalPropetyList
            )
        }
    }

    func testViewOnceMessage() {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.authorAci = authorAci
            builder.isViewOnceMessage = true
        }
        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editMessageStoreMock = EditMessageStoreMock()
        let editManager = EditManagerImpl(context:
            .init(
                attachmentStore: AttachmentStoreMock(),
                dataStore: dataStoreMock,
                editManagerAttachments: MockEditManagerAttachments(),
                editMessageStore: editMessageStoreMock,
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        db.write { tx in
            do {
                OWSAssertionError.test_skipAssertions = true
                defer {
                    OWSAssertionError.test_skipAssertions = false
                }
                _ = try editManager.processIncomingEditMessage(
                    editMessage,
                    serverTimestamp: 1,
                    serverGuid: UUID().uuidString,
                    serverDeliveryTimestamp: 1234,
                    thread: thread,
                    editTarget: .incomingMessage(IncomingEditMessageWrapper(
                        message: targetMessage,
                        thread: thread,
                        authorAci: authorAci
                    )),
                    tx: tx
                )
                XCTFail("Expected error")
            } catch {
                // Success!
            }
        }
    }

    func testContactShareEditMessageFails() {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.authorAci = authorAci
        }

        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editMessageStoreMock = EditMessageStoreMock()
        let editManager = EditManagerImpl(context:
            .init(
                attachmentStore: AttachmentStoreMock(),
                dataStore: dataStoreMock,
                editManagerAttachments: MockEditManagerAttachments(),
                editMessageStore: editMessageStoreMock,
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        dataStoreMock.isContactShare = true

        db.write { tx in
            do {
                OWSAssertionError.test_skipAssertions = true
                defer {
                    OWSAssertionError.test_skipAssertions = false
                }
                _ = try editManager.processIncomingEditMessage(
                    editMessage,
                    serverTimestamp: 1,
                    serverGuid: UUID().uuidString,
                    serverDeliveryTimestamp: 1234,
                    thread: thread,
                    editTarget: .incomingMessage(IncomingEditMessageWrapper(
                        message: targetMessage,
                        thread: thread,
                        authorAci: authorAci
                    )),
                    tx: tx
                )
                XCTFail("Expected error")
            } catch {
                // Success!
            }
        }
    }

    func testExpiredEditWindow() {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.authorAci = authorAci
        }
        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editMessageStoreMock = EditMessageStoreMock()

        let editManager = EditManagerImpl(context:
            .init(
                attachmentStore: AttachmentStoreMock(),
                dataStore: dataStoreMock,
                editManagerAttachments: MockEditManagerAttachments(),
                editMessageStore: editMessageStoreMock,
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        let expiredTS = targetMessage.receivedAtTimestamp + EditManagerImpl.Constants.editWindowMilliseconds + 1

        db.write { tx in
            do {
                OWSAssertionError.test_skipAssertions = true
                defer {
                    OWSAssertionError.test_skipAssertions = false
                }
                _ = try editManager.processIncomingEditMessage(
                    editMessage,
                    serverTimestamp: expiredTS,
                    serverGuid: UUID().uuidString,
                    serverDeliveryTimestamp: 1234,
                    thread: thread,
                    editTarget: .incomingMessage(IncomingEditMessageWrapper(
                        message: targetMessage,
                        thread: thread,
                        authorAci: authorAci
                    )),
                    tx: tx
                )
                XCTFail("Expected error")
            } catch {
                // Success!
            }
        }
    }

    func testOverflowEditWindow() {
        let bigInt: UInt64 = .max - 100
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.authorAci = authorAci
            builder.serverTimestamp = bigInt
        }
        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editMessageStoreMock = EditMessageStoreMock()

        let editManager = EditManagerImpl(context:
            .init(
                attachmentStore: AttachmentStoreMock(),
                dataStore: dataStoreMock,
                editManagerAttachments: MockEditManagerAttachments(),
                editMessageStore: editMessageStoreMock,
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        db.write { tx in
            do {
                OWSAssertionError.test_skipAssertions = true
                defer {
                    OWSAssertionError.test_skipAssertions = false
                }
                _ = try editManager.processIncomingEditMessage(
                    editMessage,
                    serverTimestamp: bigInt + 1,
                    serverGuid: UUID().uuidString,
                    serverDeliveryTimestamp: 1234,
                    thread: thread,
                    editTarget: .incomingMessage(IncomingEditMessageWrapper(
                        message: targetMessage,
                        thread: thread,
                        authorAci: authorAci
                    )),
                    tx: tx
                )
                XCTFail("Expected error")
            } catch {
                // Success!
            }
        }
    }

    func testEditSendWindowString() {
        let errorMessage = EditSendValidationError.editWindowClosed.localizedDescription
        let editMilliseconds = EditManagerImpl.Constants.editSendWindowMilliseconds
        XCTAssertEqual(editMilliseconds % UInt64.hourInMs, 0)
        XCTAssert(errorMessage.range(of: " \(editMilliseconds / UInt64.hourInMs) ") != nil)
    }

    // MARK: - Test Validation Helper

    func compare(
        _ a: AnyObject?,
        _ b: AnyObject?,
        propertyList: [String: EditedMessageValidationType]
    ) {
        guard let a, let b else {
            XCTFail("Missing object")
            return
        }

        // Create a set of predefined property keys to
        // track which have been seen
        var propertySet = Set(propertyList.keys)

        var count: CUnsignedInt = 0
        let result = class_copyPropertyList(TSMessage.self, &count)
        for index in 0..<Int(count) {
            if
                let result,
                let key = NSString(utf8String: property_getName(result[index])) as? String
            {
                if let property = propertyList[key] {
                    switch property {
                    case .ignore:
                        break
                    case .unchanged:
                        // check match
                        let val1 = a.value(forKey: key)
                        let val2 = b.value(forKey: key)
                        XCTAssertEqual(
                            String(describing: val1),
                            String(describing: val2)
                        )
                    case .changed:
                        // check diff
                        let val1 = a.value(forKey: key)
                        let val2 = b.value(forKey: key)
                        if val1 != nil && val2 != nil {
                            XCTAssertNotEqual(
                                String(describing: val1),
                                String(describing: val2)
                            )
                        }
                    }
                    propertySet.remove(key)
                } else {
                    // check for any extra fields on the object
                    XCTFail("Defined list of properties missing field (\(key)) found on object")
                }
            }
        }
        // check for any remainging fields in the predefined list
        if propertySet.isEmpty.negated {
            XCTFail("Defined list of properties contains field(s) (\(propertySet)) missing on object")
        }
    }

    // MARK: - Test Utility

    private func createEditDataMessage(
        customizationBlock: ((SSKProtoDataMessageBuilder) -> Void)
    ) -> SSKProtoDataMessage {
        let dataBuilder = SSKProtoDataMessage.builder()
        dataBuilder.setTimestamp(2) // set a default timestamp
        customizationBlock(dataBuilder)
        return try! dataBuilder.build()
    }

    private func createIncomingMessage(
        with thread: TSThread,
        customizeBlock: ((TSIncomingMessageBuilder) -> Void)
    ) -> TSIncomingMessage {
        let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread
        )
        messageBuilder.serverTimestamp = 1
        customizeBlock(messageBuilder)
        let targetMessage = messageBuilder.build()
        targetMessage.replaceRowId(1, uniqueId: "1")
        return targetMessage
    }

    // MARK: - Test Mocks

    private class EditManagerDataStoreMock: EditManagerImpl.Shims.DataStore {
        func createOutgoingEditMessage(
            thread: TSThread,
            targetMessageTimestamp: UInt64,
            editMessage: TSOutgoingMessage,
            tx: DBReadTransaction
        ) -> OutgoingEditMessage {
            return try! OutgoingEditMessage(dictionary: [:])
        }

        func build(
            _ builder: TSOutgoingMessageBuilder,
            tx: DBReadTransaction
        ) -> TSOutgoingMessage {
            return builder.build(transaction: SDSDB.shimOnlyBridge(tx))
        }

        var isContactShare = false

        func isMessageContactShare(_ message: TSMessage) -> Bool {
            return isContactShare
        }

        func update(
            _ message: TSOutgoingMessage,
            withRecipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?,
            tx: DBWriteTransaction
        ) {}

        let targetMessage: TSMessage?
        var editMessageCopy: TSMessage?
        var oldMessageCopy: TSMessage?

        init(targetMessage: TSMessage?) {
            self.targetMessage = targetMessage
        }

        func insert(_ message: TSMessage, tx: DBWriteTransaction) {
            oldMessageCopy = message
            message.replaceRowId(2, uniqueId: message.uniqueId)
        }

        func overwritingUpdate(_ message: TSMessage, tx: DBWriteTransaction) {
            editMessageCopy = message
        }
    }

    private class EditMessageStoreMock: EditMessageStore {
        func editTarget(
            timestamp: UInt64,
            authorAci: Aci?,
            tx: DBReadTransaction
        ) -> EditMessageTarget? {
            return nil
        }

        func findMessage(
            fromEdit edit: TSMessage,
            tx: DBReadTransaction
        ) -> TSMessage? {
            nil
        }

        func numberOfEdits(
            for message: TSMessage,
            tx: DBReadTransaction
        ) -> Int {
            return 1
        }

        func findEditHistory<MessageType: TSMessage>(
            for message: MessageType,
            tx: DBReadTransaction
        ) throws -> [(record: EditRecord, message: MessageType?)] {
            return []
        }

        func findEditDeleteRecords<MessageType: TSMessage>(
            for message: MessageType,
            tx: DBReadTransaction
        ) throws -> [(record: EditRecord, message: MessageType?)] {
            return []
        }

        var editRecord: EditRecord?

        func insert(_ editRecord: EditRecord, tx: DBWriteTransaction) {
            self.editRecord = editRecord
        }

        func update(_ editRecord: EditRecord, tx: DBWriteTransaction) throws {}

    }

    private class ReceiptManagerMock: EditManagerImpl.Shims.ReceiptManager {
        func messageWasRead(
            _ message: TSIncomingMessage,
            thread: TSThread,
            circumstance: OWSReceiptCircumstance,
            tx: DBWriteTransaction) { }
    }

    // MARK: - Test Data

    /// There are three types
    ///     'match': The values before and after should always match.
    ///     'change': If the value is present, it should change before and after the edit
    ///     'ignore': Properties that arent checked in these tests
    enum EditedMessageValidationType {
        case unchanged
        case changed
        case ignore
    }

    let editPropertyList: [String: EditedMessageValidationType] = [
        "isIncoming": .unchanged,
        "isOutgoing": .unchanged,
        "editState": .changed,
        "body": .changed,
        "bodyRanges": .changed,
        "expiresInSeconds": .unchanged,
        "expireTimerVersion": .unchanged,
        "expireStartedAt": .unchanged,
        "schemaVersion": .unchanged,
        "quotedMessage": .unchanged,
        "contactShare": .unchanged,
        "linkPreview": .unchanged,
        "messageSticker": .unchanged,
        "isSmsMessageRestoredFromBackup": .unchanged,
        "isViewOnceMessage": .unchanged,
        "isViewOnceComplete": .unchanged,
        "wasRemotelyDeleted": .unchanged,
        "storyReactionEmoji": .unchanged,
        "storedShouldStartExpireTimer": .unchanged,
        "deprecated_attachmentIds": .unchanged,
        "expiresAt": .unchanged,
        "hasPerConversationExpiration": .unchanged,
        "hasPerConversationExpirationStarted": .unchanged,
        "giftBadge": .unchanged,
        "storyTimestamp": .unchanged,
        "storyAuthorAci": .unchanged,
        "storyAuthorAddress": .unchanged,
        "storyAuthorUuidString": .unchanged,
        "isGroupStoryReply": .unchanged,
        "isStoryReply": .unchanged,
        "hash": .ignore,
        "superclass": .ignore,
        "description": .ignore,
        "debugDescription": .ignore
    ]

    let originalPropetyList: [String: EditedMessageValidationType] = [
        "isIncoming": .unchanged,
        "isOutgoing": .unchanged,
        "editState": .changed,
        "body": .unchanged,
        "bodyRanges": .unchanged,
        "expiresInSeconds": .unchanged,
        "expireTimerVersion": .unchanged,
        "expireStartedAt": .unchanged,
        "schemaVersion": .unchanged,
        "quotedMessage": .unchanged,
        "contactShare": .unchanged,
        "linkPreview": .unchanged,
        "messageSticker": .unchanged,
        "isSmsMessageRestoredFromBackup": .unchanged,
        "isViewOnceMessage": .unchanged,
        "isViewOnceComplete": .unchanged,
        "wasRemotelyDeleted": .unchanged,
        "storyReactionEmoji": .unchanged,
        "storedShouldStartExpireTimer": .unchanged,
        "deprecated_attachmentIds": .unchanged,
        "expiresAt": .unchanged,
        "hasPerConversationExpiration": .unchanged,
        "hasPerConversationExpirationStarted": .unchanged,
        "giftBadge": .unchanged,
        "storyTimestamp": .unchanged,
        "storyAuthorAci": .unchanged,
        "storyAuthorAddress": .unchanged,
        "storyAuthorUuidString": .unchanged,
        "isGroupStoryReply": .unchanged,
        "isStoryReply": .unchanged,
        "hash": .ignore,
        "superclass": .ignore,
        "description": .ignore,
        "debugDescription": .ignore
    ]
}
