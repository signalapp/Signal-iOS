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
    private let mockTSAccountManager = MockTSAccountManager()
    var pollAuthorAci: Aci!

    init() {
        pollMessageManager = PollMessageManager(
            pollStore: PollStore(),
            recipientDatabaseTable: RecipientDatabaseTable(),
            interactionStore: InteractionStoreImpl(),
            accountManager: mockTSAccountManager,
            db: db
        )
        let testPhone = E164("+16505550101")!
        pollAuthorAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")
        let pni = Pni(fromUUID: UUID())
        contactThread = TSContactThread(contactAddress: SignalServiceAddress(
            serviceId: pollAuthorAci,
            phoneNumber: testPhone.stringValue,
            cache: SignalServiceAddressCache()
        ))
        recipient = SignalRecipient(aci: pollAuthorAci, pni: pni, phoneNumber: testPhone)
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

    private func insertIncomingPollMessage(question: String, timestamp: UInt64? = nil) -> TSIncomingMessage {
        db.write { tx in
            let db = tx.database
            if try! contactThread.asRecord().exists(db) == false {
                try! contactThread!.asRecord().insert(db)
            }

            let incomingMessage = createIncomingMessage(with: contactThread) { builder in
                builder.setMessageBody(AttachmentContentValidatorMock.mockValidatedBody(question))
                builder.authorAci = pollAuthorAci
                builder.isPoll = true
                if let timestamp {
                    builder.timestamp = timestamp
                }
            }
            try! incomingMessage.asRecord().insert(db)
            return incomingMessage
        }
    }

    private func insertOutgoingPollMessage(question: String) -> TSOutgoingMessage {
        db.write { tx in
            let db = tx.database
            if try! contactThread.asRecord().exists(db) == false {
                try! contactThread!.asRecord().insert(db)
            }

            let outgoingMessage = TSOutgoingMessage(in: contactThread, question: question)
            try! outgoingMessage.asRecord().insert(db)
            return outgoingMessage
        }
    }

    private func insertSignalRecipient(aci: Aci, pni: Pni, phoneNumber: E164) {
        db.write { tx in
            recipientDatabaseTable.insertRecipient(
                SignalRecipient(
                    aci: aci,
                    pni: pni,
                    phoneNumber: phoneNumber
                ),
                transaction: tx
            )
        }
    }

    private func buildPollCreateProto(question: String, options: [String], allowMultiple: Bool) -> SSKProtoDataMessagePollCreate {
        let pollCreateBuilder = SSKProtoDataMessagePollCreate.builder()
        pollCreateBuilder.setQuestion(question)
        pollCreateBuilder.setOptions(options)
        pollCreateBuilder.setAllowMultiple(allowMultiple)
        return pollCreateBuilder.buildInfallibly()
    }

    private func buildPollTerminateProto(targetSentTimestamp: UInt64) -> SSKProtoDataMessagePollTerminate {
        let pollTerminateBuilder = SSKProtoDataMessagePollTerminate.builder()
        pollTerminateBuilder.setTargetSentTimestamp(targetSentTimestamp)
        return pollTerminateBuilder.buildInfallibly()
    }

    private func buildPollVoteProto(
        pollAuthor: Aci,
        targetSentTimestamp: UInt64,
        optionIndexes: [OWSPoll.OptionIndex],
        voteCount: UInt32
    ) -> SSKProtoDataMessagePollVote {
        let pollVoteBuilder = SSKProtoDataMessagePollVote.builder()
        pollVoteBuilder.setTargetAuthorAciBinary(pollAuthor.serviceIdBinary)
        pollVoteBuilder.setTargetSentTimestamp(targetSentTimestamp)
        pollVoteBuilder.setOptionIndexes(optionIndexes)
        pollVoteBuilder.setVoteCount(voteCount)
        return pollVoteBuilder.buildInfallibly()
    }

    @Test
    func testPollCreate() throws {
        let question = "What should we have for breakfast?"
        _ = insertIncomingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
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
            #expect(pollOptions.first!.id == 1)
            #expect(pollOptions.first!.pollId == 1)
            #expect(pollOptions.first!.option == "pancakes")
            #expect(pollOptions.first!.optionIndex == 0)
            #expect(pollOptions.last!.id == 2)
            #expect(pollOptions.last!.pollId == 1)
            #expect(pollOptions.last!.option == "waffles")
            #expect(pollOptions.last!.optionIndex == 1)
        }
    }

    @Test
    func testIncomingPollTerminate() throws {
        let question = "What should we have for breakfast?"
        let incomingMessage = insertIncomingPollMessage(question: question)
        let pollCreateProto = buildPollCreateProto(
            question: question,
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

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!
        )

        try db.write { tx in
            var vote1 = PollVoteRecord(optionId: 1, voteAuthorId: 1, voteCount: 1)
            try vote1.insert(tx.database)
        }

        let terminateProto = buildPollTerminateProto(targetSentTimestamp: incomingMessage.timestamp)

        try db.write { tx in
            _ = try pollMessageManager.processIncomingPollTerminate(
                pollTerminateProto: terminateProto,
                terminateAuthor: pollAuthorAci,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == true)
            #expect(owsPoll!.totalVotes() == 1)
        }
    }

    @Test
    func testOutgoingPollTerminate() throws {
        mockTSAccountManager.localIdentifiersMock = {
            return LocalIdentifiers(
                aci: pollAuthorAci,
                pni: Pni(fromUUID: UUID()),
                e164: E164("+16505550101")!
            )
        }

        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)
        try db.write { tx in
            try pollMessageManager.processOutgoingPollCreate(
                interactionId: outgoingMessage.grdbId as! Int64,
                pollOptions: ["pancakes", "waffles"],
                allowsMultiSelect: false,
                transaction: tx
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!
        )

        try db.write { tx in
            var vote1 = PollVoteRecord(optionId: 1, voteAuthorId: 1, voteCount: 1)
            try vote1.insert(tx.database)
        }

        let terminateProto = buildPollTerminateProto(targetSentTimestamp: outgoingMessage.timestamp)

        try db.write { tx in
            _ = try pollMessageManager.processIncomingPollTerminate(
                pollTerminateProto: terminateProto,
                terminateAuthor: pollAuthorAci,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == true)
            #expect(owsPoll!.totalVotes() == 1)
        }
    }

    @Test
    func testIncomingPollVote() throws {
        mockTSAccountManager.localIdentifiersMock = {
            return LocalIdentifiers(
                aci: pollAuthorAci,
                pni: Pni(fromUUID: UUID()),
                e164: E164("+16505550101")!
            )
        }

        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)

        try db.write { tx in
            try pollMessageManager.processOutgoingPollCreate(
                interactionId: outgoingMessage.grdbId as! Int64,
                pollOptions: ["pancakes", "waffles"],
                allowsMultiSelect: false,
                transaction: tx
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000002")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!
        )

        let pollWaffleVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: outgoingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 1
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollWaffleVoteProto,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == false)
            #expect(owsPoll!.totalVotes() == 1)

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.contains(voterAci))
        }

        // Revoke vote for waffle and send it to pancake
        let pollVoteProtoRevoke = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: outgoingMessage.timestamp,
            optionIndexes: [0],
            voteCount: 2
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProtoRevoke,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.isEmpty)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(voterAci))
        }

        // Voting with multiple options should fail to update votes
        let pollVoteProtoMultiple = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: outgoingMessage.timestamp,
            optionIndexes: [0, 1],
            voteCount: 3
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProtoMultiple,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.isEmpty)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(voterAci))
        }
    }

    @Test
    func testOutgoingPollVote() throws {
        let question = "What should we have for breakfast?"
        let incomingMessage = insertIncomingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
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

        // Before voting, insert voters into Signal Recipient Table
        // which is referenced by id in the vote table.
        let waffleVoterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")
        let pancakeVoterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000002")

        insertSignalRecipient(
            aci: waffleVoterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!
        )
        insertSignalRecipient(
            aci: pancakeVoterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2"),
            phoneNumber: E164("+16505550102")!
        )

        let pollWaffleVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 1
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: waffleVoterAci,
                pollVoteProto: pollWaffleVoteProto,
                transaction: tx
            )
        }

        let pollPancakesVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0],
            voteCount: 1
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: pancakeVoterAci,
                pollVoteProto: pollPancakesVoteProto,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == false)
            #expect(owsPoll!.totalVotes() == 2)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(pancakeVoterAci))

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.contains(waffleVoterAci))
        }

        // Revoke vote for pancake and send it to waffle
        let pollVoteProtoRevoke = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 2
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: pancakeVoterAci,
                pollVoteProto: pollVoteProtoRevoke,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.isEmpty)

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.contains(waffleVoterAci))
            #expect(wafflesOption!.acis.contains(pancakeVoterAci))
        }

        // Voting with multiple options should fail to update votes
        let pollVoteProtoMultiple = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0, 1],
            voteCount: 3
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: pancakeVoterAci,
                pollVoteProto: pollVoteProtoMultiple,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.isEmpty)

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.contains(waffleVoterAci))
            #expect(wafflesOption!.acis.contains(pancakeVoterAci))
        }
    }

    @Test
    func testPollVote_multiSelection() throws {
        let question = "What should we have for breakfast?"
        let incomingMessage = insertIncomingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: true
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!
        )

        let pollVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0, 1],
            voteCount: 1
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProto,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == true)
            #expect(owsPoll!.isEnded == false)
            #expect(owsPoll!.totalVotes() == 2)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(voterAci))

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.contains(voterAci))
        }

        // Revoke vote for waffle
        let pollVoteProtoRevoke = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0],
            voteCount: 2
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProtoRevoke,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.totalVotes() == 1)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(voterAci))

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.isEmpty)
        }
    }

    @Test
    func testPollVote_dontOverwriteVoteWithOldVoteCount() throws {
        let question = "What should we have for breakfast?"
        let incomingMessage = insertIncomingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: true
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!
        )

        let pollVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0], // pancakes
            voteCount: 2
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProto,
                transaction: tx
            )
        }

        // Now send old voteCount with a different vote (waffles)
        let oldPollVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 1
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: oldPollVoteProto,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.totalVotes() == 1)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(voterAci))

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.isEmpty)
        }
    }

    @Test
    func testMultiplePollsSameAuthor() throws {
        let question1 = "What should we have for breakfast?"
        let incomingMessage1 = insertIncomingPollMessage(question: question1)

        // Make sure these don't have the same timestamp because thats used to ID polls.
        let question2 = "What is your favorite animal?"
        let incomingMessage2 = insertIncomingPollMessage(question: question2, timestamp: incomingMessage1.timestamp + 1)

        let poll1CreateProto = buildPollCreateProto(
            question: question1,
            options: ["pancakes", "waffles"],
            allowMultiple: false
        )

        let poll2CreateProto = buildPollCreateProto(
            question: question2,
            options: ["dog", "cat"],
            allowMultiple: false
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: poll1CreateProto,
                transaction: tx
            )

            try pollMessageManager.processIncomingPollCreate(
                interactionId: 2,
                pollCreateProto: poll2CreateProto,
                transaction: tx
            )
        }

        // Before voting, insert voters into Signal Recipient Table
        // which is referenced by id in the vote table.
        let user1Aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")
        let user2Aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000002")

        insertSignalRecipient(
            aci: user1Aci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!
        )
        insertSignalRecipient(
            aci: user2Aci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2"),
            phoneNumber: E164("+16505550102")!
        )

        // user1 is going to vote for pancakes, and dogs
        let user1VoteProto1 = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage1.timestamp,
            optionIndexes: [0], // pancakes
            voteCount: 1
        )

        let user1VoteProto2 = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage2.timestamp,
            optionIndexes: [0], // dog
            voteCount: 1
        )

        try db.write { tx in
            _ = try pollMessageManager.processIncomingPollVote(
                voteAuthor: user1Aci,
                pollVoteProto: user1VoteProto1,
                transaction: tx
            )

            _ = try pollMessageManager.processIncomingPollVote(
                voteAuthor: user1Aci,
                pollVoteProto: user1VoteProto2,
                transaction: tx
            )
        }

        // user2 is going to vote for waffles, and dogs
        let user2VoteProto1 = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage1.timestamp,
            optionIndexes: [1], // waffles
            voteCount: 1
        )

        let user2VoteProto2 = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage2.timestamp,
            optionIndexes: [0], // dog
            voteCount: 1
        )

        try db.write { tx in
            _ = try pollMessageManager.processIncomingPollVote(
                voteAuthor: user2Aci,
                pollVoteProto: user2VoteProto1,
                transaction: tx
            )

            _ = try pollMessageManager.processIncomingPollVote(
                voteAuthor: user2Aci,
                pollVoteProto: user2VoteProto2,
                transaction: tx
            )
        }

        try db.read { tx in
            // Poll 1 - pancakes and waffles
            let owsPoll1 = try pollMessageManager.buildPoll(message: incomingMessage1, transaction: tx)
            #expect(owsPoll1!.question == question1)
            #expect(owsPoll1!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll1!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll1!.allowsMultiSelect == false)
            #expect(owsPoll1!.isEnded == false)
            #expect(owsPoll1!.totalVotes() == 2)

            let pancakesOption = owsPoll1!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(user1Aci))

            let wafflesOption = owsPoll1!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.contains(user2Aci))

            // Poll 2 - dogs and cats
            let owsPoll2 = try pollMessageManager.buildPoll(message: incomingMessage2, transaction: tx)
            #expect(owsPoll2!.question == question2)
            #expect(owsPoll2!.sortedOptions()[0].text == "dog")
            #expect(owsPoll2!.sortedOptions()[1].text == "cat")
            #expect(owsPoll2!.allowsMultiSelect == false)
            #expect(owsPoll2!.isEnded == false)
            #expect(owsPoll2!.totalVotes() == 2)

            let dogOption = owsPoll2!.optionForIndex(optionIndex: 0)
            #expect(dogOption!.acis == [user1Aci, user2Aci])

            let catOption = owsPoll2!.optionForIndex(optionIndex: 1)
            #expect(catOption!.acis.isEmpty)
        }
    }

    @Test
    func testPollEnded() throws {
        let question = "What should we have for breakfast?"
        let incomingMessage = insertIncomingPollMessage(question: question)

        var poll = PollRecord(interactionId: 1, allowsMultiSelect: false)
        poll.isEnded = true

        try db.write { tx in
            try poll.insert(tx.database)
        }

        var option = PollOptionRecord(pollId: poll.id!, option: "test", optionIndex: 0)
        try db.write { tx in
            try option.insert(tx.database)
        }

        // Before voting, insert voters into Signal Recipient Table
        // which is referenced by id in the vote table.
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: aci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!
        )

        let proto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 1
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: aci,
                pollVoteProto: proto,
                transaction: tx
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.isEnded == true)
            #expect(owsPoll!.totalVotes() == 0)
        }
    }
}

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, question: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody(question),
            isPoll: true
        )
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
