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
    private let pollMessageManager: PollMessageManager
    private var contactThread: TSContactThread!
    private var recipient: SignalRecipient!
    var authorAci: Aci!

    init() {
        pollMessageManager = PollMessageManager(
            pollStore: PollStore(),
            recipientDatabaseTable: RecipientDatabaseTable(),
            interactionStore: InteractionStoreImpl()
        )
        let testPhone = E164("+16505550101")!
        authorAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")
        let pni = Pni(fromUUID: UUID())
        contactThread = TSContactThread(contactAddress: SignalServiceAddress(
            serviceId: authorAci,
            phoneNumber: testPhone.stringValue,
            cache: SignalServiceAddressCache()
        ))
        recipient = SignalRecipient(aci: authorAci, pni: pni, phoneNumber: testPhone)
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
            try pollMessageManager.processIncomingPollCreate(
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

    @Test
    func testPollBuild() throws {
        let incomingMessage = createIncomingMessage(with: contactThread) { builder in
            builder.setMessageBody(AttachmentContentValidatorMock.mockValidatedBody("What should we have for breakfast"))
            builder.authorAci = authorAci
            builder.isPoll = true
        }

        db.write { tx in
            let db = tx.database
            try! contactThread!.asRecord().insert(db)
            try! incomingMessage.asRecord().insert(db)
            RecipientDatabaseTable().insertRecipient(recipient, transaction: tx)
        }

        let pollCreateProto = buildPollCreateProto(
            question: "What should we have for breakfast",
            options: ["pancakes", "waffles"],
            allowMultiple: false
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx
            )
        }

        try db.write { tx in
            var vote1 = PollVoteRecord(optionId: 1, voteAuthorId: 1, voteCount: 1)
            try vote1.insert(tx.database)
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == "What should we have for breakfast")
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == false)
            #expect(owsPoll!.totalVotes() == 1)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(authorAci))

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.isEmpty)
        }
    }
}
