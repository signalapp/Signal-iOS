//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class EditManagerTests: SSKBaseTestSwift {
    var db: DB!
    var authorAci: AciObjC!
    var thread: TSThread!

    override func setUp() {
        super.setUp()
        db = MockDB()
        authorAci = AciObjC(Aci.constantForTesting("00000000-0000-4000-8000-000000000000"))
        thread = TSThread(uniqueId: "1")
    }

    func testBasicValidation() {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.messageBody = "BAR"
            builder.authorAci = authorAci
            builder.expireStartedAt = 3
        }

        let editMessage = createEditDataMessage { $0.setBody("FOO") }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
                linkPreviewShim: LinkPreviewMock(),
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                editTarget: .incomingMessage(IncomingEditMessageWrapper(
                    message: targetMessage,
                    authorAci: authorAci.wrappedAciValue
                )),
                serverTimestamp: 1,
                tx: tx
            )

            XCTAssertNotNil(result)

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
        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
                linkPreviewShim: LinkPreviewMock(),
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                editTarget: .incomingMessage(IncomingEditMessageWrapper(
                    message: targetMessage,
                    authorAci: authorAci.wrappedAciValue
                )),
                serverTimestamp: 1,
                tx: tx
            )
            XCTAssertNil(result)
        }
    }

    func testContactShareEditMessageFails() {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.authorAci = authorAci
            builder.contactShare = OWSContact()
        }

        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
                linkPreviewShim: LinkPreviewMock(),
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                editTarget: .incomingMessage(IncomingEditMessageWrapper(
                    message: targetMessage,
                    authorAci: authorAci.wrappedAciValue
                )),
                serverTimestamp: 1,
                tx: tx
            )
            XCTAssertNil(result)
        }
    }

    func testExpiredEditWindow() {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.authorAci = authorAci
        }
        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)

        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
                linkPreviewShim: LinkPreviewMock(),
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        let expiredTS = targetMessage.receivedAtTimestamp + EditManager.Constants.editWindowMilliseconds + 1

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                editTarget: .incomingMessage(IncomingEditMessageWrapper(
                    message: targetMessage,
                    authorAci: authorAci.wrappedAciValue
                )),
                serverTimestamp: expiredTS,
                tx: tx
            )
            XCTAssertNil(result)
        }
    }

    func testOverflowEditWindow() {
        let bigInt: UInt64 = .max - 100
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.authorAci = authorAci
            builder.serverTimestamp = NSNumber(value: bigInt)
        }
        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)

        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
                linkPreviewShim: LinkPreviewMock(),
                receiptManagerShim: ReceiptManagerMock()
            )
        )

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                editTarget: .incomingMessage(IncomingEditMessageWrapper(
                    message: targetMessage,
                    authorAci: authorAci.wrappedAciValue
                )),
                serverTimestamp: bigInt + 1,
                tx: tx
            )
            XCTAssertNil(result)
        }
    }

    func testEditSendWindowString() {
        let errorMessage = EditSendValidationError.editWindowClosed.localizedDescription
        let editMilliseconds = EditManager.Constants.editSendWindowMilliseconds
        XCTAssertEqual(editMilliseconds % UInt64(kHourInMs), 0)
        XCTAssert(errorMessage.range(of: " \(editMilliseconds / UInt64(kHourInMs)) ") != nil)
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
        dataBuilder.setTimestamp(1) // set a default timestamp
        customizationBlock(dataBuilder)
        return try! dataBuilder.build()
    }

    private func createIncomingMessage(
        with thread: TSThread,
        customizeBlock: ((TSIncomingMessageBuilder) -> Void)
    ) -> TSIncomingMessage {
        let messageBuilder = TSIncomingMessageBuilder.incomingMessageBuilder(
            thread: thread
        )
        messageBuilder.serverTimestamp = NSNumber(value: 0)
        customizeBlock(messageBuilder)
        let targetMessage = messageBuilder.build()
        targetMessage.replaceRowId(1, uniqueId: "1")
        return targetMessage
    }

    // MARK: - Test Mocks

    private class EditManagerDataStoreMock: EditManager.Shims.DataStore {
        func createOutgoingEditMessage(
            thread: TSThread,
            targetMessageTimestamp: UInt64,
            editMessage: TSOutgoingMessage,
            tx: DBReadTransaction
        ) -> OutgoingEditMessage {
            return try! OutgoingEditMessage(dictionary: [:])
        }

        func findEditTarget(
            timestamp: UInt64,
            authorAci: Aci?,
            tx: DBReadTransaction
        ) -> EditMessageTarget? {
            return nil
        }

        func createOutgoingMessage(
            with builder: TSOutgoingMessageBuilder,
            tx: DBReadTransaction) -> TSOutgoingMessage {
                return builder.build(transaction: SDSDB.shimOnlyBridge(tx))
        }

        func copyRecipients(
            from source: TSOutgoingMessage,
            to target: TSOutgoingMessage,
            tx: DBWriteTransaction) {
        }

        let targetMessage: TSMessage?
        var editMessageCopy: TSMessage?
        var oldMessageCopy: TSMessage?
        var editRecord: EditRecord?
        var attachment: TSAttachment?

        init(targetMessage: TSMessage?) {
            self.targetMessage = targetMessage
        }

        func getMediaAttachments(
            message: TSMessage,
            tx: DBReadTransaction
        ) -> [TSAttachment] {
            return []
        }

        func getOversizedTextAttachments(
            message: TSMessage,
            tx: DBReadTransaction
        ) -> TSAttachment? {
            return nil
        }

        func insertMessageCopy(message: TSMessage, tx: DBWriteTransaction) {
            oldMessageCopy = message
            message.replaceRowId(2, uniqueId: message.uniqueId)
        }

        func updateEditedMessage(message: TSMessage, tx: DBWriteTransaction) {
            editMessageCopy = message
        }

        func insertEditRecord(record: EditRecord, tx: DBWriteTransaction) {
            editRecord = record
        }

        func insertAttachment(
            attachment: TSAttachmentPointer,
            tx: DBWriteTransaction
        ) {
            self.attachment = attachment
        }

        func numberOfEdits(for message: TSMessage, tx: DBReadTransaction) -> Int { 1 }

        func findEditHistory(
            for message: TSMessage,
            tx: DBReadTransaction
        ) throws -> [(EditRecord, TSMessage?)] {
            return []
        }

        func update(
            editRecord: EditRecord,
            tx: DBWriteTransaction
        ) throws {}
    }

    private class LinkPreviewMock: EditManager.Shims.LinkPreview {
        func buildPreview(
            dataMessage: SSKProtoDataMessage,
            tx: DBWriteTransaction
        ) throws -> OWSLinkPreview {
            return OWSLinkPreview()
        }
    }

    private class GroupsMock: EditManager.Shims.Groups {
        func groupId(for message: SSKProtoDataMessage) -> GroupV2ContextInfo? {
            return nil
        }
    }

    private class ReceiptManagerMock: EditManager.Shims.ReceiptManager {
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
        "expireStartedAt": .unchanged,
        "schemaVersion": .unchanged,
        "quotedMessage": .unchanged,
        "contactShare": .unchanged,
        "linkPreview": .unchanged,
        "messageSticker": .unchanged,
        "isViewOnceMessage": .unchanged,
        "isViewOnceComplete": .unchanged,
        "wasRemotelyDeleted": .unchanged,
        "storyReactionEmoji": .unchanged,
        "storedShouldStartExpireTimer": .unchanged,
        "attachmentIds": .unchanged,
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
        "expireStartedAt": .unchanged,
        "schemaVersion": .unchanged,
        "quotedMessage": .unchanged,
        "contactShare": .unchanged,
        "linkPreview": .unchanged,
        "messageSticker": .unchanged,
        "isViewOnceMessage": .unchanged,
        "isViewOnceComplete": .unchanged,
        "wasRemotelyDeleted": .unchanged,
        "storyReactionEmoji": .unchanged,
        "storedShouldStartExpireTimer": .unchanged,
        "attachmentIds": .unchanged,
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
