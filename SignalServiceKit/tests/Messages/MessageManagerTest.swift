//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

final class MessageManagerTest: SSKBaseTestSwift {
    private let kLocalE164 = "+13215550198"
    private let kLocalAci = "B0D19730-950B-462C-84E7-60421F879EEF"

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: kLocalE164, uuid: UUID(uuidString: kLocalAci)!)
        sskJobQueues.messageSenderJobQueue.setup()
    }

    func testIncomingSyncGroupsMessage() throws {
        let messageWasSent = expectation(description: "message was sent")
        (syncManager as! OWSMockSyncManager).syncGroupsHook = { messageWasSent.fulfill() }

        let requestBuilder = SSKProtoSyncMessageRequest.builder()
        requestBuilder.setType(.groups)

        let messageBuilder = SSKProtoSyncMessage.builder()
        messageBuilder.setRequest(requestBuilder.buildInfallibly())

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: 12345)
        envelopeBuilder.setType(.ciphertext)
        envelopeBuilder.setSourceUuid(kLocalAci)
        envelopeBuilder.setSourceDevice(1)

        try write { tx in
            messageManager.handleIncomingEnvelope(
                try envelopeBuilder.build(),
                with: try messageBuilder.build(),
                plaintextData: Data(),
                wasReceivedByUD: false,
                serverDeliveryTimestamp: 0,
                transaction: tx
            )
        }

        waitForExpectations(timeout: 5)
    }

    func testGroupUpdate() throws {
        // GroupsV2 TODO: Handle v2 groups.
        let groupId = TSGroupModel.generateRandomV1GroupId()

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: 12345)
        envelopeBuilder.setSourceUuid(UUID().uuidString)
        envelopeBuilder.setSourceDevice(1)
        envelopeBuilder.setType(.ciphertext)
        envelopeBuilder.setServerTimestamp(1)

        let groupContextBuilder = SSKProtoGroupContext.builder(id: groupId)
        groupContextBuilder.setType(.update)
        groupContextBuilder.setName("Newly created Group Name")

        let messageBuilder = SSKProtoDataMessage.builder()
        messageBuilder.setGroup(try groupContextBuilder.build())

        let validatedEnvelope = try ValidatedIncomingEnvelope(try envelopeBuilder.build())
        let identifiedEnvelope = try IdentifiedIncomingEnvelope(validatedEnvelope: validatedEnvelope)

        try write { tx in
            messageManager.handle(
                identifiedEnvelope,
                with: try messageBuilder.build(),
                plaintextData: Data(),
                wasReceivedByUD: false,
                serverDeliveryTimestamp: 0,
                shouldDiscardVisibleMessages: false,
                transaction: tx
            )
        }

        read { tx in
            let thread = TSGroupThread.fetch(groupId: groupId, transaction: tx)
            XCTAssertEqual(thread?.groupNameOrDefault, "Newly created Group Name")
        }
    }

    func testGroupUpdateWithAvatar() throws {
        // GroupsV2 TODO: Handle v2 groups.
        let groupId = TSGroupModel.generateRandomV1GroupId()

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: 12345)
        envelopeBuilder.setSourceUuid(UUID().uuidString)
        envelopeBuilder.setSourceDevice(1)
        envelopeBuilder.setType(.ciphertext)
        envelopeBuilder.setServerTimestamp(1)

        let groupContextBuilder = SSKProtoGroupContext.builder(id: groupId)
        groupContextBuilder.setType(.update)
        groupContextBuilder.setName("Newly created Group Name")

        let attachmentBuilder = SSKProtoAttachmentPointer.builder()
        attachmentBuilder.setCdnID(1234)
        attachmentBuilder.setContentType("image/png")
        attachmentBuilder.setKey(Cryptography.generateRandomBytes(32))
        attachmentBuilder.setSize(123)
        groupContextBuilder.setAvatar(attachmentBuilder.buildInfallibly())

        let messageBuilder = SSKProtoDataMessage.builder()
        messageBuilder.setGroup(try groupContextBuilder.build())

        let validatedEnvelope = try ValidatedIncomingEnvelope(try envelopeBuilder.build())
        let identifiedEnvelope = try IdentifiedIncomingEnvelope(validatedEnvelope: validatedEnvelope)

        try write { tx in
            messageManager.handle(
                identifiedEnvelope,
                with: try messageBuilder.build(),
                plaintextData: Data(),
                wasReceivedByUD: false,
                serverDeliveryTimestamp: 0,
                shouldDiscardVisibleMessages: false,
                transaction: tx
            )
        }

        read { tx in
            let thread = TSGroupThread.fetch(groupId: groupId, transaction: tx)
            XCTAssertEqual(thread?.groupNameOrDefault, "Newly created Group Name")
        }
    }
}
