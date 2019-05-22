//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension DebugUIMessages {

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
}
