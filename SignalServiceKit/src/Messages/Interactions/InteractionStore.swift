//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol InteractionStore {
    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction)
}

class InteractionStoreImpl: InteractionStore {
    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

class MockInteractionStore: InteractionStore {
    var insertedInteractions = [TSInteraction]()
    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        insertedInteractions.append(interaction)
    }
}

#endif
