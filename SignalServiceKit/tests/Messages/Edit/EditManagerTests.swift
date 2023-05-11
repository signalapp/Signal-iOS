//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class EditManagerTests: SSKBaseTestSwift {
    var db: DB!
    var author: SignalServiceAddress!
    var thread: TSThread!

    override func setUp() {
        super.setUp()
        db = MockDB()
        author = SignalServiceAddress(phoneNumber: "+12345678900")
        thread = TSThread(uniqueId: "1")
    }

    func testBasicValidation() {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.messageBody = "BAR"
            builder.authorAddress = author
            builder.expireStartedAt = 3
        }

        let editMessage = createEditDataMessage { $0.setBody("FOO") }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                linkPreviewShim: LinkPreviewMock()
            )
        )

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                serverTimestamp: 0,
                targetTimestamp: 0,
                author: author,
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
            builder.authorAddress = author
            builder.isViewOnceMessage = true
        }
        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                linkPreviewShim: LinkPreviewMock()
            )
        )

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                serverTimestamp: 0,
                targetTimestamp: 0,
                author: author,
                tx: tx
            )
            XCTAssertNil(result)
        }
    }

    func testContactShareEditMessageFails() {
        let targetMessage = createIncomingMessage(with: thread) { builder in
            builder.authorAddress = author
            builder.contactShare = OWSContact()
        }

        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)
        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                linkPreviewShim: LinkPreviewMock()
            )
        )

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                serverTimestamp: 0,
                targetTimestamp: 0,
                author: author,
                tx: tx
            )
            XCTAssertNil(result)
        }
    }

    func testMissingTargetMessage() {
        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: nil)
        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                linkPreviewShim: LinkPreviewMock()
            )
        )

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                serverTimestamp: 0,
                targetTimestamp: 0,
                author: author,
                tx: tx
            )
            XCTAssertNil(result)
        }
    }

    func testExpiredEditWindow() {
        let targetMessage = createIncomingMessage(with: thread) {
            $0.authorAddress = author
        }
        let editMessage = createEditDataMessage { _ in }
        let dataStoreMock = EditManagerDataStoreMock(targetMessage: targetMessage)

        let editManager = EditManager(context:
            .init(
                dataStore: dataStoreMock,
                groupsShim: GroupsMock(),
                linkPreviewShim: LinkPreviewMock()
            )
        )

        let expiredTS = targetMessage.receivedAtTimestamp + EditManager.Constants.editWindow + 1

        db.write { tx in
            let result = editManager.processIncomingEditMessage(
                editMessage,
                thread: thread,
                serverTimestamp: expiredTS,
                targetTimestamp: 0,
                author: author,
                tx: tx
            )
            XCTAssertNil(result)
        }
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
        customizeBlock(messageBuilder)
        let targetMessage = messageBuilder.build()
        targetMessage.replaceRowId(1, uniqueId: "1")
        return targetMessage
    }

    // MARK: - Test Mocks

    private class EditManagerDataStoreMock: EditManager.Shims.DataStore {

        let targetMessage: TSMessage?
        var editMessageCopy: TSMessage?
        var oldMessageCopy: TSMessage?
        var editRecord: EditRecord?
        var attachment: TSAttachment?

        init(targetMessage: TSMessage?) {
            self.targetMessage = targetMessage
        }

        func findTargetMessage(timestamp: UInt64, author: SignalServiceAddress, tx: DBReadTransaction) -> TSInteraction? {
            return targetMessage
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
        "isSyncMessage": .unchanged,
        "canSendToLocalAddress": .unchanged,
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
        "isSyncMessage": .unchanged,
        "canSendToLocalAddress": .unchanged,
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
