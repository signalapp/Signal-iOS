//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

open class MockInteractionDeleteManager: InteractionDeleteManager {
    var deleteInteractionMock: ((
        _ interaction: TSInteraction,
        _ associatedCallDeleteBehavior: AssociatedCallDeleteBehavior
    ) -> Void)?
    open func delete(_ interaction: TSInteraction, associatedCallDeleteBehavior: AssociatedCallDeleteBehavior, tx: any DBWriteTransaction) {
        deleteInteractionMock!(interaction, associatedCallDeleteBehavior)
    }

    var deleteAlongsideCallRecordsMock: ((
        _ callRecords: [CallRecord],
        _ associatedCallDeleteBehavior: AssociatedCallDeleteBehavior
    ) -> Void)?
    open func delete(alongsideAssociatedCallRecords callRecords: [CallRecord], associatedCallDeleteBehavior: AssociatedCallDeleteBehavior, tx: any DBWriteTransaction) {
        deleteAlongsideCallRecordsMock!(callRecords, associatedCallDeleteBehavior)
    }

    var deleteAllMock: (() -> Void)?
    open func deleteAll(tx: any DBWriteTransaction) {
        deleteAllMock!()
    }
}

#endif
