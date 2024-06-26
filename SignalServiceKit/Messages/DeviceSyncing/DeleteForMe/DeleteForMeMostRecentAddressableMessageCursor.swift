//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A cursor over the most recent "addressable messages", or those that were
/// sent to or received from other users and can therefore be located across
/// devices.
///
/// In practice, these are ``TSIncomingMessage``s or ``TSOutgoingMessage``s.
/// This type provides a cursor interface over the most recent instances of both
/// for a particular thread, ordered by SQLite row ID descending.
final class DeleteForMeMostRecentAddressableMessageCursor: InterleavingCompositeCursor<DeleteForMeAddressableMessageInterleavableCursor> {

    /// Construct a highly efficient cursor over the most recent addressable
    /// messages in the thread with the given unique ID.
    convenience init(threadUniqueId: String, sdsTx: SDSAnyReadTransaction) throws {
        try self.init(addressableMessageCursors: [
            MostRecentIncomingMessageCursor(threadUniqueId: threadUniqueId, sdsTx: sdsTx),
            MostRecentOutgoingMessageCursor(threadUniqueId: threadUniqueId, sdsTx: sdsTx),
        ])
    }

    /// Construct an interleaved cursor over the given addressable-message
    /// cursors. The given cursors must be ordered descending, and should return
    /// their next element in O(1) time.
    init(addressableMessageCursors: [DeleteForMeAddressableMessageCursor]) throws {
        try super.init(
            interleaving: addressableMessageCursors.map { DeleteForMeAddressableMessageInterleavableCursor(addressableMessageCursor: $0) },
            nextElementComparator: { lhs, rhs in
                guard let lhsRowId = lhs.sqliteRowId, let rhsRowId = rhs.sqliteRowId else {
                    owsFail("Cursor-fetched interactions missing SQLite row IDs!")
                }

                return lhsRowId > rhsRowId
            }
        )
    }
}

// MARK: -

protocol DeleteForMeAddressableMessageCursor {
    func nextAddressableMessage() throws -> TSMessage?
}

struct DeleteForMeAddressableMessageInterleavableCursor: InterleavableCursor {
    private let addressableMessageCursor: DeleteForMeAddressableMessageCursor

    init(addressableMessageCursor: DeleteForMeAddressableMessageCursor) {
        self.addressableMessageCursor = addressableMessageCursor
    }

    // MARK: InterleavableCursor

    typealias InterleavableElement = TSMessage

    func nextInterleavableElement() throws -> TSMessage? {
        return try addressableMessageCursor.nextAddressableMessage()
    }
}

// MARK: -

/// An O(1) descending cursor over all ``TSIncomingMessage``s for a thread.
private struct MostRecentIncomingMessageCursor: DeleteForMeAddressableMessageCursor {
    private let interactionCursor: TSInteractionCursor

    init(threadUniqueId: String, sdsTx: SDSAnyReadTransaction) {
        self.interactionCursor = InteractionFinder(
            threadUniqueId: threadUniqueId
        ).buildIncomingMessagesCursor(
            rowIdFilter: .newest,
            tx: sdsTx
        )
    }

    func nextAddressableMessage() throws -> TSMessage? {
        return try interactionCursor.next().map { $0 as! TSIncomingMessage }
    }
}

/// An O(1) descending cursor over all ``TSOutgoingMessage``s for a thread.
private struct MostRecentOutgoingMessageCursor: DeleteForMeAddressableMessageCursor {
    private let interactionCursor: TSInteractionCursor

    init(threadUniqueId: String, sdsTx: SDSAnyReadTransaction) {
        self.interactionCursor = InteractionFinder(
            threadUniqueId: threadUniqueId
        ).buildOutgoingMessagesCursor(
            rowIdFilter: .newest,
            tx: sdsTx
        )
    }

    func nextAddressableMessage() throws -> TSMessage? {
        return try interactionCursor.next().map { $0 as! TSOutgoingMessage }
    }
}
