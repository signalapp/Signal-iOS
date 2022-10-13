//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if DEBUG

public extension DebugUIMessages {

    @objc
    class func deleteRandomMessages(count: UInt, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.info("deleteRandomMessages: \(count)")

        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)

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
        messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                      serverDeliveryTimestamp: 0,
                                                      envelopeSource: .debugUI) { _ in }
    }

    @objc
    class func createUUIDGroup() {
        let uuidMembers = (0...3).map { _ in CommonGenerator.address(hasPhoneNumber: false) }
        let members = uuidMembers + [TSAccountManager.localAddress!]
        let groupName = "UUID Group"

        _ = GroupManager.localCreateNewGroup(members: members, name: groupName, disappearingMessageToken: .disabledToken, shouldSendMessage: true)
    }
}

#endif
