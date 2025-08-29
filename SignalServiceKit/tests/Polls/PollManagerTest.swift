//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import LibSignalClient
@testable import SignalServiceKit

@MainActor
struct PollManagerTest {
    private let db = InMemoryDB()
    private let recipientDatabaseTable = RecipientDatabaseTable()
    private let pollManager: PollManager
    private var contactThread: TSContactThread!
    var authorAci: Aci!

    init() {
        pollManager = PollManager(
            pollStore: PollStore(),
            recipientDatabaseTable: RecipientDatabaseTable(),
            interactionStore: InteractionStoreImpl()
        )
        let testPhone = E164("+16505550101")!
        authorAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")
        contactThread = TSContactThread(contactAddress: SignalServiceAddress(
            serviceId: authorAci,
            phoneNumber: testPhone.stringValue,
            cache: SignalServiceAddressCache()
        ))
    }

    private func createIncomingMessage(
        with thread: TSThread,
        customizeBlock: ((TSIncomingMessageBuilder) -> Void)
    ) -> TSIncomingMessage {
        let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread
        )
        customizeBlock(messageBuilder)
        let targetMessage = messageBuilder.build()
        return targetMessage
    }

    private func buildPollCreateProto(question: String, options: [String], allowMultiple: Bool) -> SSKProtoDataMessagePollCreate {
        let pollCreateBuilder = SSKProtoDataMessagePollCreate.builder()
        pollCreateBuilder.setQuestion(question)
        pollCreateBuilder.setOptions(options)
        pollCreateBuilder.setAllowMultiple(allowMultiple)
        return pollCreateBuilder.buildInfallibly()
    }

    @Test
    func testPollCreate() throws {
        db.write { tx in
            let db = tx.database
            try! contactThread!.asRecord().insert(db)

            let incomingMessage = createIncomingMessage(with: contactThread) { builder in
                builder.setMessageBody(AttachmentContentValidatorMock.mockValidatedBody("What should we have for breakfast"))
                builder.authorAci = authorAci
                builder.isPoll = true
            }
            try! incomingMessage.asRecord().insert(db)
        }

        let pollCreateProto = buildPollCreateProto(
            question: "What should we have for breakfast",
            options: ["pancakes", "waffles"],
            allowMultiple: false
        )

        try db.write { tx in
            try pollManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx
            )
        }

        try db.read { tx in
            let pollRecords = try PollRecord.fetchAll(tx.database)
            #expect(pollRecords.count == 1)
            #expect(pollRecords.first!.interactionId == 1)
            #expect(pollRecords.first!.allowsMultiSelect == false)
        }

        try db.read { tx in
            let pollOptions = try PollOptionRecord.fetchAll(tx.database)
            #expect(pollOptions.count == 2)
            #expect(pollOptions.first!.pollId == 1)
            #expect(pollOptions.first!.option == "pancakes")
            #expect(pollOptions.first!.optionIndex == 0)
            #expect(pollOptions.last!.pollId == 1)
            #expect(pollOptions.last!.option == "waffles")
            #expect(pollOptions.last!.optionIndex == 1)
        }
    }
}
