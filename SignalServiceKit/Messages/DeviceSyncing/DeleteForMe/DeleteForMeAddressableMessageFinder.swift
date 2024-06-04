//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

protocol DeleteForMeAddressableMessageFinder {
    typealias Conversation = DeleteForMeSyncMessage.Conversation
    typealias AddressableMessage = DeleteForMeSyncMessage.AddressableMessage

    func findMostRecentAddressableMessages(
        threadUniqueId: String,
        maxCount: Int,
        tx: any DBReadTransaction
    ) -> [AddressableMessage]

    func findLocalMessage(
        conversation: Conversation,
        addressableMessage: AddressableMessage,
        tx: any DBReadTransaction
    ) -> TSMessage?
}

extension DeleteForMeAddressableMessageFinder {
    func threadContainsAnyAddressableMessages(
        threadUniqueId: String,
        tx: any DBReadTransaction
    ) -> Bool {
        let mostRecentAddressableMessage = findMostRecentAddressableMessages(
            threadUniqueId: threadUniqueId,
            maxCount: 1,
            tx: tx
        ).first

        return mostRecentAddressableMessage != nil
    }
}

// MARK: -

final class DeleteForMeAddressableMessageFinderImpl: DeleteForMeAddressableMessageFinder {
    private let threadStore: ThreadStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let tsAccountManager: TSAccountManager

    init(
        threadStore: ThreadStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        tsAccountManager: TSAccountManager
    ) {
        self.threadStore = threadStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.tsAccountManager = tsAccountManager
    }

    func findMostRecentAddressableMessages(
        threadUniqueId: String,
        maxCount: Int = 5,
        tx: any DBReadTransaction
    ) -> [AddressableMessage] {
        var addressableMessages = [AddressableMessage]()

        do {
            try DeleteForMeMostRecentAddressableMessageCursor(
                threadUniqueId: threadUniqueId,
                sdsTx: SDSDB.shimOnlyBridge(tx)
            ).iterate { addressableMessage -> Bool in
                if let incomingMessage = addressableMessage as? TSIncomingMessage {
                    guard let signalRecipient = recipientDatabaseTable.fetchAuthorRecipient(
                        incomingMessage: incomingMessage,
                        tx: tx
                    ) else {
                        owsFailDebug("Failed to get recipient for message author!")
                        // Continue iterating.
                        return true
                    }

                    addressableMessages.append(AddressableMessage(
                        author: .otherUser(signalRecipient),
                        sentTimestamp: incomingMessage.timestamp
                    ))
                } else if let outgoingMessage = addressableMessage as? TSOutgoingMessage {
                    addressableMessages.append(AddressableMessage(
                        author: .localUser,
                        sentTimestamp: outgoingMessage.timestamp
                    ))
                } else {
                    owsFail("Unexpected interaction type!")
                }

                // Continue iterating until we have `maxCount` items.
                return addressableMessages.count < maxCount
            }
        } catch {
            owsFailDebug("Failed to enumerate interactions!")
            return []
        }

        return addressableMessages
    }

    func findLocalMessage(
        conversation: Conversation,
        addressableMessage: AddressableMessage,
        tx: any DBReadTransaction
    ) -> TSMessage? {
        let authorAddress: SignalServiceAddress
        switch addressableMessage.author {
        case .localUser:
            guard let localAddress = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
                return nil
            }
            authorAddress = localAddress
        case .otherUser(let signalRecipient):
            authorAddress = signalRecipient.address
        }

        return InteractionFinder.findMessage(
            withTimestamp: addressableMessage.sentTimestamp,
            threadId: conversation.threadUniqueId,
            author: authorAddress,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}
