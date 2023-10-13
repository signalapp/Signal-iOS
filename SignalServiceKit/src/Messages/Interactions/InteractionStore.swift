//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol InteractionStore {
    /// Fetch the interaction with the given SQLite row ID, if one exists.
    func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction?

    /// Insert the given interaction to the databse.
    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction)

    /// Applies the given block to the given already-inserted interaction, and
    /// saves the updated interaction to the database.
    func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void
    )
}

class InteractionStoreImpl: InteractionStore {
    func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return InteractionFinder.fetch(
            rowId: interactionRowId, transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void
    ) {
        interaction.anyUpdate(transaction: SDSDB.shimOnlyBridge(tx)) { interaction in
            guard let interaction = interaction as? InteractionType else {
                owsFailBeta("Interaction of unexpected type! \(type(of: interaction))")
                return
            }

            block(interaction)
        }
    }
}

#if TESTABLE_BUILD

class MockInteractionStore: InteractionStore {
    var insertedInteractions = [TSInteraction]()

    func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return insertedInteractions.first(where: { $0.sqliteRowId == interactionRowId })
    }

    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.updateRowId(.random(in: 0...Int64.max))
        insertedInteractions.append(interaction)
    }

    func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void
    ) {
        block(interaction)
    }
}

#endif
