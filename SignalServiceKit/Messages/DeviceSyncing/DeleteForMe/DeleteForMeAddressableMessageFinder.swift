//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

protocol DeleteForMeAddressableMessageFinder {
    func findLocalMessage(
        threadUniqueId: String,
        addressableMessage: AddressableMessage,
        tx: DBReadTransaction,
    ) -> TSMessage?

    func threadContainsAnyAddressableMessages(
        threadUniqueId: String,
        tx: DBReadTransaction,
    ) -> Bool
}

// MARK: -

final class DeleteForMeAddressableMessageFinderImpl: DeleteForMeAddressableMessageFinder {
    func findLocalMessage(
        threadUniqueId: String,
        addressableMessage: AddressableMessage,
        tx: DBReadTransaction,
    ) -> TSMessage? {
        let authorAddress: SignalServiceAddress
        switch addressableMessage.author {
        case .aci(let aci):
            authorAddress = SignalServiceAddress(aci)
        case .e164(let e164):
            authorAddress = SignalServiceAddress(e164)
        }

        return InteractionFinder.findMessage(
            withTimestamp: addressableMessage.sentTimestamp,
            threadId: threadUniqueId,
            author: authorAddress,
            transaction: tx,
        )
    }

    func threadContainsAnyAddressableMessages(
        threadUniqueId: String,
        tx: DBReadTransaction,
    ) -> Bool {
        var foundAddressableMessage = false

        do {
            try DeleteForMeMostRecentAddressableMessageCursor(
                threadUniqueId: threadUniqueId,
                sdsTx: tx,
            ).iterate { interaction in
                owsPrecondition(
                    interaction is TSIncomingMessage || interaction is TSOutgoingMessage,
                    "Unexpected interaction type! \(type(of: interaction))",
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
    func findLocalMessage(threadUniqueId: String, addressableMessage: AddressableMessage, tx: DBReadTransaction) -> TSMessage? {
        return nil
    }

    func threadContainsAnyAddressableMessages(threadUniqueId: String, tx: DBReadTransaction) -> Bool {
        return false
    }
}

#endif
