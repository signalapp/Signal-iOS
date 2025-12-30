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
    private let pollStore = PollStore()
    private var groupThread: TSGroupThread!
    private var recipient: SignalRecipient!
    private let mockTSAccountManager = MockTSAccountManager()
    private let pollAuthorAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000000")

    init() throws {
        pollMessageManager = PollMessageManager(
            pollStore: pollStore,
            recipientDatabaseTable: RecipientDatabaseTable(),
            interactionStore: InteractionStoreImpl(),
            accountManager: mockTSAccountManager,
            messageSenderJobQueue: MessageSenderJobQueue(appReadiness: AppReadinessMock()),
            disappearingMessagesConfigurationStore: MockDisappearingMessagesConfigurationStore(),
            attachmentContentValidator: AttachmentContentValidatorMock(),
            db: db,
        )
        let pollAuthorPhoneNumber = E164("+16505550100")!
        let pollAuthorPni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b0")
        groupThread = TSGroupThread.randomForTesting()
        recipient = db.write { tx in
            return try! SignalRecipient.insertRecord(aci: pollAuthorAci, phoneNumber: pollAuthorPhoneNumber, pni: pollAuthorPni, tx: tx)
        }
    }

    private func createIncomingMessage(
        with thread: TSThread,
        customizeBlock: (TSIncomingMessageBuilder) -> Void,
    ) -> TSIncomingMessage {
        let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread,
        )
        customizeBlock(messageBuilder)
        let targetMessage = messageBuilder.build()
        return targetMessage
    }

    private func insertIncomingPollMessage(question: String, timestamp: UInt64? = nil) -> TSIncomingMessage {
        db.write { tx in
            let db = tx.database
            if try! groupThread.asRecord().exists(db) == false {
                try! groupThread!.asRecord().insert(db)
            }

            let incomingMessage = createIncomingMessage(with: groupThread) { builder in
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
            if try! groupThread.asRecord().exists(db) == false {
                try! groupThread!.asRecord().insert(db)
            }

            let outgoingMessage = TSOutgoingMessage(in: groupThread, question: question)
            try! outgoingMessage.asRecord().insert(db)
            return outgoingMessage
        }
    }

    private func insertSignalRecipient(aci: Aci, pni: Pni, phoneNumber: E164) {
        db.write { tx in
            _ = try! SignalRecipient.insertRecord(aci: aci, phoneNumber: phoneNumber, pni: pni, tx: tx)
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
        voteCount: UInt32,
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
            allowMultiple: false,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
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
            allowMultiple: false,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!,
        )

        try db.write { tx in
            var vote1 = PollVoteRecord(optionId: 1, voteAuthorId: 1, voteCount: 1, voteState: .vote)
            try vote1.insert(tx.database)
        }

        let terminateProto = buildPollTerminateProto(targetSentTimestamp: incomingMessage.timestamp)

        try db.write { tx in
            _ = try pollMessageManager.processIncomingPollTerminate(
                pollTerminateProto: terminateProto,
                terminateAuthor: pollAuthorAci,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == true)
            #expect(owsPoll!.totalVoters() == 1)
        }
    }

    @Test
    func testOutgoingPollTerminate() throws {
        mockTSAccountManager.localIdentifiersMock = {
            return LocalIdentifiers(
                aci: pollAuthorAci,
                pni: Pni(fromUUID: UUID()),
                e164: E164("+16505550101")!,
            )
        }

        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)
        try db.write { tx in
            try pollMessageManager.processOutgoingPollCreate(
                interactionId: outgoingMessage.grdbId as! Int64,
                pollOptions: ["pancakes", "waffles"],
                allowsMultiSelect: false,
                transaction: tx,
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!,
        )

        try db.write { tx in
            var vote1 = PollVoteRecord(optionId: 1, voteAuthorId: 1, voteCount: 1, voteState: .vote)
            try vote1.insert(tx.database)
        }

        let terminateProto = buildPollTerminateProto(targetSentTimestamp: outgoingMessage.timestamp)

        try db.write { tx in
            _ = try pollMessageManager.processIncomingPollTerminate(
                pollTerminateProto: terminateProto,
                terminateAuthor: pollAuthorAci,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == true)
            #expect(owsPoll!.totalVoters() == 1)
        }
    }

    @Test
    func testIncomingPollVote() throws {
        mockTSAccountManager.localIdentifiersMock = {
            return LocalIdentifiers(
                aci: pollAuthorAci,
                pni: Pni(fromUUID: UUID()),
                e164: E164("+16505550101")!,
            )
        }

        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)

        try db.write { tx in
            try pollMessageManager.processOutgoingPollCreate(
                interactionId: outgoingMessage.grdbId as! Int64,
                pollOptions: ["pancakes", "waffles"],
                allowsMultiSelect: false,
                transaction: tx,
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000002")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!,
        )

        let pollWaffleVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: outgoingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 1,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollWaffleVoteProto,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == false)
            #expect(owsPoll!.totalVoters() == 1)

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.contains(voterAci))
        }

        // Revoke vote for waffle and send it to pancake
        let pollVoteProtoRevoke = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: outgoingMessage.timestamp,
            optionIndexes: [0],
            voteCount: 2,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProtoRevoke,
                transaction: tx,
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
            voteCount: 3,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProtoMultiple,
                transaction: tx,
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
            allowMultiple: false,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        // Before voting, insert voters into Signal Recipient Table
        // which is referenced by id in the vote table.
        let waffleVoterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")
        let pancakeVoterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000002")

        insertSignalRecipient(
            aci: waffleVoterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!,
        )
        insertSignalRecipient(
            aci: pancakeVoterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2"),
            phoneNumber: E164("+16505550102")!,
        )

        let pollWaffleVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 1,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: waffleVoterAci,
                pollVoteProto: pollWaffleVoteProto,
                transaction: tx,
            )
        }

        let pollPancakesVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0],
            voteCount: 1,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: pancakeVoterAci,
                pollVoteProto: pollPancakesVoteProto,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == false)
            #expect(owsPoll!.isEnded == false)
            #expect(owsPoll!.totalVoters() == 2)

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
            voteCount: 2,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: pancakeVoterAci,
                pollVoteProto: pollVoteProtoRevoke,
                transaction: tx,
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
            voteCount: 3,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: pancakeVoterAci,
                pollVoteProto: pollVoteProtoMultiple,
                transaction: tx,
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
            allowMultiple: true,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!,
        )

        let pollVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0, 1],
            voteCount: 1,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProto,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.sortedOptions()[0].text == "pancakes")
            #expect(owsPoll!.sortedOptions()[1].text == "waffles")
            #expect(owsPoll!.allowsMultiSelect == true)
            #expect(owsPoll!.isEnded == false)
            #expect(owsPoll!.totalVoters() == 1)

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
            voteCount: 2,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProtoRevoke,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.totalVoters() == 1)

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
            allowMultiple: true,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!,
        )

        let pollVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0], // pancakes
            voteCount: 2,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProto,
                transaction: tx,
            )
        }

        // Now send old voteCount with a different vote (waffles)
        let oldPollVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 1,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: oldPollVoteProto,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.contains(voterAci))

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.isEmpty)
        }
    }

    @Test
    func testPollVote_dontOverwriteUnvoteWithOldVoteCount() throws {
        let question = "What should we have for breakfast?"
        let incomingMessage = insertIncomingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: true,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        // Before voting, insert voter into Signal Recipient Table
        // which is referenced by id in the vote table.
        let voterAci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")

        insertSignalRecipient(
            aci: voterAci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!,
        )

        let pollVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [0], // pancakes
            voteCount: 2,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollVoteProto,
                transaction: tx,
            )
        }

        // Now send an unvote with a higher vote count
        let pollUnVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [], // unvote for pancakes
            voteCount: 4,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: pollUnVoteProto,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.totalVoters() == 0)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.isEmpty)

            let wafflesOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(wafflesOption!.acis.isEmpty)
        }

        // Now send old voteCount with a different vote (waffles)
        let oldPollVoteProto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 3,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: voterAci,
                pollVoteProto: oldPollVoteProto,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.totalVoters() == 0)

            let pancakesOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakesOption!.acis.isEmpty)

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
            allowMultiple: false,
        )

        let poll2CreateProto = buildPollCreateProto(
            question: question2,
            options: ["dog", "cat"],
            allowMultiple: false,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: poll1CreateProto,
                transaction: tx,
            )

            try pollMessageManager.processIncomingPollCreate(
                interactionId: 2,
                pollCreateProto: poll2CreateProto,
                transaction: tx,
            )
        }

        // Before voting, insert voters into Signal Recipient Table
        // which is referenced by id in the vote table.
        let user1Aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000001")
        let user2Aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000002")

        insertSignalRecipient(
            aci: user1Aci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1"),
            phoneNumber: E164("+16505550101")!,
        )
        insertSignalRecipient(
            aci: user2Aci,
            pni: Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b2"),
            phoneNumber: E164("+16505550102")!,
        )

        // user1 is going to vote for pancakes, and dogs
        let user1VoteProto1 = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage1.timestamp,
            optionIndexes: [0], // pancakes
            voteCount: 1,
        )

        let user1VoteProto2 = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage2.timestamp,
            optionIndexes: [0], // dog
            voteCount: 1,
        )

        try db.write { tx in
            _ = try pollMessageManager.processIncomingPollVote(
                voteAuthor: user1Aci,
                pollVoteProto: user1VoteProto1,
                transaction: tx,
            )

            _ = try pollMessageManager.processIncomingPollVote(
                voteAuthor: user1Aci,
                pollVoteProto: user1VoteProto2,
                transaction: tx,
            )
        }

        // user2 is going to vote for waffles, and dogs
        let user2VoteProto1 = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage1.timestamp,
            optionIndexes: [1], // waffles
            voteCount: 1,
        )

        let user2VoteProto2 = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage2.timestamp,
            optionIndexes: [0], // dog
            voteCount: 1,
        )

        try db.write { tx in
            _ = try pollMessageManager.processIncomingPollVote(
                voteAuthor: user2Aci,
                pollVoteProto: user2VoteProto1,
                transaction: tx,
            )

            _ = try pollMessageManager.processIncomingPollVote(
                voteAuthor: user2Aci,
                pollVoteProto: user2VoteProto2,
                transaction: tx,
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
            #expect(owsPoll1!.totalVoters() == 2)

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
            #expect(owsPoll2!.totalVoters() == 2)

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
            phoneNumber: E164("+16505550101")!,
        )

        let proto = buildPollVoteProto(
            pollAuthor: pollAuthorAci,
            targetSentTimestamp: incomingMessage.timestamp,
            optionIndexes: [1],
            voteCount: 1,
        )

        _ = try db.write { tx in
            try pollMessageManager.processIncomingPollVote(
                voteAuthor: aci,
                pollVoteProto: proto,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: incomingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.isEnded == true)
            #expect(owsPoll!.totalVoters() == 0)
        }
    }

    @Test
    func testPendingThenSentVote_singleSelect() throws {
        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: false,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        let signalRecipient = db.read { tx in
            recipientDatabaseTable.fetchRecipient(serviceId: pollAuthorAci, transaction: tx)
        }

        var voteCount = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: false,
                transaction: tx,
            )
        }

        // Pending vote should not count as a vote.
        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 0)
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0)], // pancakes,
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount!),
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [pollAuthorAci])
        }

        // Unvote
        voteCount = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: true,
                transaction: tx,
            )
        }

        // Since unvote is still pending, the vote is still valid.
        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [pollAuthorAci])
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [], // unvote
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount!),
                transaction: tx,
            )
        }

        // Sent unvote should now be finalized.
        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 0)
        }
    }

    @Test
    func testPendingThenSentVote_multiSelect() throws {
        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: true,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        let signalRecipient = db.read { tx in
            recipientDatabaseTable.fetchRecipient(serviceId: pollAuthorAci, transaction: tx)
        }

        var voteCount = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: false,
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0)], // pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount!),
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [pollAuthorAci])
        }

        // Vote for another option.
        voteCount = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        // pending waffle vote should not affect pancakes vote.
        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [pollAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis.isEmpty)
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(1), OWSPoll.OptionIndex(0)],
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount!),
                transaction: tx,
            )
        }

        // Sent second vote should now be finalized.
        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [pollAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis == [pollAuthorAci])
        }

        // Unvote for pancakes
        voteCount = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: true,
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(1)], // waffles only
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount!),
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis.isEmpty)

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis == [pollAuthorAci])
        }
    }

    @Test
    func testMultiplePendingBeforeSent_multi() throws {
        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: true,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        let signalRecipient = db.read { tx in
            recipientDatabaseTable.fetchRecipient(serviceId: pollAuthorAci, transaction: tx)
        }

        let voteCount1 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: false,
                transaction: tx,
            )
        }

        let voteCount2 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 0)
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0)], // pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount1!),
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0), OWSPoll.OptionIndex(1)], // waffles + pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount2!),
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [pollAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis == [pollAuthorAci])
        }
    }

    @Test
    func testOutOfOrderPendingAndSent() throws {
        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: true,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        let signalRecipient = db.read { tx in
            recipientDatabaseTable.fetchRecipient(serviceId: pollAuthorAci, transaction: tx)
        }

        let voteCount1 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: false,
                transaction: tx,
            )
        }

        let voteCount2 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 0)
        }

        // Send vote count 2 first, state should be updated
        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0), OWSPoll.OptionIndex(1)], // waffles + pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount2!),
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [pollAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis == [pollAuthorAci])
        }

        // Now send vote count 1 -> should be ignored.
        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0)], // pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount1!),
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [pollAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis == [pollAuthorAci])
        }
    }

    @Test
    func testSendFails_singleSelect() throws {
        let question = "What should we have for breakfast?"

        var voteAuthorAci: Aci
        let message = insertOutgoingPollMessage(question: question)
        voteAuthorAci = pollAuthorAci

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: false,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        let signalRecipient = db.read { tx in
            recipientDatabaseTable.fetchRecipient(serviceId: voteAuthorAci, transaction: tx)
        }

        let voteCount1 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: message.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: false,
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: message.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0)], // pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount1!),
                transaction: tx,
            )
        }

        // send pending message for another, different vote
        let voteCount2 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: message.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        // Simulate vote fail, and rollback to old state
        try db.write { tx in
            try pollStore.revertVoteCount(
                voteCount: voteCount2!,
                interactionId: message.grdbId!.int64Value,
                voteAuthorId: signalRecipient!.id,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: message, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [voteAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis.isEmpty)
        }

        // Now send successful vote
        let voteCount3 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: message.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: message.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(1)], // waffles
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount3!),
                transaction: tx,
            )
        }

        // send pending message for unvote
        let voteCount4 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: message.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: true,
                transaction: tx,
            )
        }

        // Simulate vote fail, and rollback to old state
        try db.write { tx in
            try pollStore.revertVoteCount(
                voteCount: voteCount4!,
                interactionId: message.grdbId!.int64Value,
                voteAuthorId: signalRecipient!.id,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: message, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis.isEmpty)

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis == [voteAuthorAci])
        }
    }

    @Test
    func testSendFails_multiSelect() throws {
        let question = "What should we have for breakfast?"

        var voteAuthorAci: Aci
        let message = insertOutgoingPollMessage(question: question)
        voteAuthorAci = pollAuthorAci

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: true,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        let signalRecipient = db.read { tx in
            recipientDatabaseTable.fetchRecipient(serviceId: voteAuthorAci, transaction: tx)
        }

        let voteCount1 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: message.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: false,
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: message.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0)], // pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount1!),
                transaction: tx,
            )
        }

        // send pending message for another, different vote
        let voteCount2 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: message.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        // Simulate vote fail, and rollback to old state
        try db.write { tx in
            try pollStore.revertVoteCount(
                voteCount: voteCount2!,
                interactionId: message.grdbId!.int64Value,
                voteAuthorId: signalRecipient!.id,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: message, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [voteAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis.isEmpty)
        }

        // Now send successful vote
        let voteCount3 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: message.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: message.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0), OWSPoll.OptionIndex(1)],
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount3!),
                transaction: tx,
            )
        }

        // send pending message for unvote
        let voteCount4 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: message.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: true,
                transaction: tx,
            )
        }

        // Simulate vote fail, and rollback to old state
        try db.write { tx in
            try pollStore.revertVoteCount(
                voteCount: voteCount4!,
                interactionId: message.grdbId!.int64Value,
                voteAuthorId: signalRecipient!.id,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: message, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [voteAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis == [voteAuthorAci])
        }
    }

    @Test
    func testSendFailsButVoteCountHasMovedOn() throws {
        let question = "What should we have for breakfast?"
        let outgoingMessage = insertOutgoingPollMessage(question: question)

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: true,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        let signalRecipient = db.read { tx in
            recipientDatabaseTable.fetchRecipient(serviceId: pollAuthorAci, transaction: tx)
        }

        // Pending vote count 1
        let voteCount1 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: false,
                transaction: tx,
            )
        }

        // Successful vote count 2
        let voteCount2 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(1)], // pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount2!),
                transaction: tx,
            )
        }

        // Simulate vote fail for voteCount 1 - should be ignored since
        // vote count has moved on.
        try db.write { tx in
            try pollStore.revertVoteCount(
                voteCount: voteCount1!,
                interactionId: outgoingMessage.grdbId!.int64Value,
                voteAuthorId: signalRecipient!.id,
                transaction: tx,
            )
        }

        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis.isEmpty)

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis == [pollAuthorAci])
        }
    }

    @Test
    func testMultipleConflictingPendingStatesFail_singleSelect() async throws {
        let question = "What should we have for breakfast?"

        var voteAuthorAci: Aci
        let outgoingMessage = insertOutgoingPollMessage(question: question)
        voteAuthorAci = pollAuthorAci

        let pollCreateProto = buildPollCreateProto(
            question: question,
            options: ["pancakes", "waffles"],
            allowMultiple: false,
        )

        try db.write { tx in
            try pollMessageManager.processIncomingPollCreate(
                interactionId: 1,
                pollCreateProto: pollCreateProto,
                transaction: tx,
            )
        }

        let signalRecipient = db.read { tx in
            recipientDatabaseTable.fetchRecipient(serviceId: voteAuthorAci, transaction: tx)
        }

        let voteCount1 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(0), // pancakes
                isUnvote: false,
                transaction: tx,
            )
        }

        _ = try db.write { tx in
            try pollStore.updatePollWithVotes(
                interactionId: outgoingMessage.grdbId!.int64Value,
                optionsVoted: [OWSPoll.OptionIndex(0)], // pancakes
                voteAuthorId: signalRecipient!.id,
                voteCount: UInt32(voteCount1!),
                transaction: tx,
            )
        }

        // send pending message for another, different vote
        let voteCount2 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: false,
                transaction: tx,
            )
        }

        // send a second pending message with a conflicting vote value (aka an unvote)
        let voteCount3 = try db.write { tx in
            try pollStore.applyPendingVote(
                interactionId: outgoingMessage.grdbId!.int64Value,
                localRecipientId: signalRecipient!.id,
                optionIndex: OWSPoll.OptionIndex(1), // waffles
                isUnvote: true,
                transaction: tx,
            )
        }

        // Now fail both.
        try db.write { tx in
            try pollStore.revertVoteCount(
                voteCount: voteCount2!,
                interactionId: outgoingMessage.grdbId!.int64Value,
                voteAuthorId: signalRecipient!.id,
                transaction: tx,
            )

            try pollStore.revertVoteCount(
                voteCount: voteCount3!,
                interactionId: outgoingMessage.grdbId!.int64Value,
                voteAuthorId: signalRecipient!.id,
                transaction: tx,
            )
        }

        // Should go back to original state of single vote for pancake.
        try db.read { tx in
            let owsPoll = try pollMessageManager.buildPoll(message: outgoingMessage, transaction: tx)
            #expect(owsPoll!.question == question)
            #expect(owsPoll!.totalVoters() == 1)

            let pancakeOption = owsPoll!.optionForIndex(optionIndex: 0)
            #expect(pancakeOption!.acis == [voteAuthorAci])

            let waffleOption = owsPoll!.optionForIndex(optionIndex: 1)
            #expect(waffleOption!.acis.isEmpty)
        }
    }
}

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, question: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody(question),
            isPoll: true,
        )
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}

private extension TSGroupThread {
    static func randomForTesting() -> TSGroupThread {
        return .forUnitTest(groupId: 12)
    }
}
