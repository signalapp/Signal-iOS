//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension DebugUIMessages {

    // MARK: - Dependencies

    static var messageReceiver: OWSMessageReceiver {
        return SSKEnvironment.shared.messageReceiver
    }

    static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    @objc
    class func deleteRandomMessages(count: UInt, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.info("deleteRandomMessages: \(count)")

        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId!)

        let messageCount = interactionFinder.count(transaction: transaction)

        var messageIndices: [UInt] = Array((0..<messageCount))
        var interactions: [TSInteraction] = []

        for _ in (0..<count) {
            guard let index = Array(0..<messageIndices.count).randomElement() else {
                break
            }

            let messageIndex = messageIndices[index]
            messageIndices.remove(at: index)

            guard let interaction = try! interactionFinder.interaction(at: messageIndex, transaction: transaction) else {
                owsFailDebug("interaction was unexpectedly nil")
                continue
            }
            interactions.append(interaction)
        }

        for interaction in interactions {
            interaction.anyRemove(transaction: transaction)
        }
    }

    @objc
    class func receiveUUIDEnvelopeInNewThread() {
        assert(FeatureFlags.allowUUIDOnlyContacts)

        let senderClient = FakeSignalClient.generate(e164Identifier: nil)
        let localClient = LocalSignalClient()
        let runner = TestProtocolRunner()
        let fakeService = FakeService(localClient: localClient, runner: runner)

        databaseStorage.write { transaction in
            try! runner.initialize(senderClient: senderClient,
                                   recipientClient: localClient,
                                   transaction: transaction)
        }

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: senderClient)
        envelopeBuilder.setSourceUuid(senderClient.uuidIdentifier)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        messageReceiver.handleReceivedEnvelopeData(envelopeData)
    }

    @objc
    class func createUUIDGroup() {
        assert(FeatureFlags.allowUUIDOnlyContacts)

        let uuidMembers = (0...3).map { _ in CommonGenerator.address(hasPhoneNumber: false) }

        let members = uuidMembers + [TSAccountManager.localAddress!]

        let groupName = "UUID Group"
        let groupId = Randomness.generateRandomBytes(kGroupIdLength)!
        let groupModel = TSGroupModel(
            title: groupName,
            members: members,
            image: nil,
            groupId: groupId
        )

        databaseStorage.write { transaction in
            let thread = TSGroupThread.getOrCreateThread(with: groupModel, transaction: transaction)
            let message = TSOutgoingMessage.init(in: thread, groupMetaMessage: .new, expiresInSeconds: 0)
            message.update(withCustomMessage: NSLocalizedString("GROUP_CREATED", comment: ""), transaction: transaction)
            SSKEnvironment.shared.messageSenderJobQueue.add(message: message, transaction: transaction)
        }
    }
}
