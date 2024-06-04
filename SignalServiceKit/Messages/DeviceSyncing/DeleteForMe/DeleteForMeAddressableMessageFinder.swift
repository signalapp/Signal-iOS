//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

protocol DeleteForMeAddressableMessageFinder {
    typealias Outgoing = DeleteForMeSyncMessage.Outgoing
    typealias Incoming = DeleteForMeSyncMessage.Incoming

    func findMostRecentAddressableMessages(
        threadUniqueId: String,
        maxCount: Int,
        localIdentifiers: LocalIdentifiers,
        tx: any DBReadTransaction
    ) -> [Outgoing.AddressableMessage]

    func findLocalMessage(
        threadUniqueId: String,
        addressableMessage: Incoming.AddressableMessage,
        tx: any DBReadTransaction
    ) -> TSMessage?

    func threadContainsAnyAddressableMessages(
        threadUniqueId: String,
        tx: any DBReadTransaction
    ) -> Bool
}

// MARK: -

final class DeleteForMeAddressableMessageFinderImpl: DeleteForMeAddressableMessageFinder {
    private let tsAccountManager: TSAccountManager

    init(tsAccountManager: TSAccountManager) {
        self.tsAccountManager = tsAccountManager
    }

    func findMostRecentAddressableMessages(
        threadUniqueId: String,
        maxCount: Int,
        localIdentifiers: LocalIdentifiers,
        tx: any DBReadTransaction
    ) -> [Outgoing.AddressableMessage] {
        var addressableMessages = [Outgoing.AddressableMessage]()

        do {
            try DeleteForMeMostRecentAddressableMessageCursor(
                threadUniqueId: threadUniqueId,
                sdsTx: SDSDB.shimOnlyBridge(tx)
            ).iterate { interaction -> Bool in
                if let incomingMessage = interaction as? TSIncomingMessage {
                    if let addressableMessage = Outgoing.AddressableMessage(
                        incomingMessage: incomingMessage
                    ) {
                        addressableMessages.append(addressableMessage)
                    } else {
                        owsFailDebug("Failed to build addressable message for incoming message!")
                    }
                } else if let outgoingMessage = interaction as? TSOutgoingMessage {
                    addressableMessages.append(Outgoing.AddressableMessage(
                        outgoingMessage: outgoingMessage,
                        localIdentifiers: localIdentifiers
                    ))
                } else {
                    owsFail("Unexpected interaction type! \(type(of: interaction))")
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
        threadUniqueId: String,
        addressableMessage: Incoming.AddressableMessage,
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
            threadId: threadUniqueId,
            author: authorAddress,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    func threadContainsAnyAddressableMessages(
        threadUniqueId: String,
        tx: any DBReadTransaction
    ) -> Bool {
        var foundAddressableMessage = false

        do {
            try DeleteForMeMostRecentAddressableMessageCursor(
                threadUniqueId: threadUniqueId,
                sdsTx: SDSDB.shimOnlyBridge(tx)
            ).iterate { interaction in
                owsAssert(
                    interaction is TSIncomingMessage || interaction is TSOutgoingMessage,
                    "Unexpected interaction type! \(type(of: interaction))"
                )

                foundAddressableMessage = true
                return false
            }
        } catch {
            owsFailDebug("Failed to enumerate interactions!")
            return false
        }

        return foundAddressableMessage
    }
}

// MARK: - Mock

#if TESTABLE_BUILD

open class MockDeleteForMeAddressableMessageFinder: DeleteForMeAddressableMessageFinder {
    func findMostRecentAddressableMessages(threadUniqueId: String, maxCount: Int, localIdentifiers: LocalIdentifiers, tx: any DBReadTransaction) -> [Outgoing.AddressableMessage] {
        return []
    }

    func findLocalMessage(threadUniqueId: String, addressableMessage: Incoming.AddressableMessage, tx: any DBReadTransaction) -> TSMessage? {
        return nil
    }

    func threadContainsAnyAddressableMessages(threadUniqueId: String, tx: any DBReadTransaction) -> Bool {
        return false
    }
}

#endif
