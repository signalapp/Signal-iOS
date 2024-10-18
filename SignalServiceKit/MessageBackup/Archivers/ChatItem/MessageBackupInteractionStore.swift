//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class MessageBackupInteractionStore {

    private let interactionStore: InteractionStore

    init(interactionStore: InteractionStore) {
        self.interactionStore = interactionStore
    }

    /// Enumerate all interactions.
    ///
    /// - Parameter block
    /// A block executed for each enumerated interaction. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: (TSInteraction) throws -> Bool
    ) throws {
        try interactionStore.enumerateAllInteractions(tx: tx, block: block)
    }

    /// Fetch all interactions with the given timestamp.
    /// Used to fetch matches for quoted reply target interactions.
    func interactions(
        withTimestamp timestamp: UInt64,
        tx: DBReadTransaction
    ) throws -> [TSInteraction] {
        return try interactionStore.interactions(withTimestamp: timestamp, tx: tx)
    }

    func insert(
        _ interaction: TSInteraction,
        in thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) throws {
        // TODO: [BackupsPerf] replicate all side effects of sds anyInsert and
        // insert directly instead of going through the store (it uses SDS save)
        interactionStore.insertInteraction(interaction, tx: context.tx)
    }
}
