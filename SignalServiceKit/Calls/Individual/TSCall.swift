//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSCall {
    private var callRecordStore: CallRecordStore {
        DependenciesBridge.shared.callRecordStore
    }

    /// Explicitly delete any ``CallRecord``s associated with this interaction.
    ///
    /// These records would be deleted automatically due to their foreign key
    /// reference to this interaction, but that auto-deletion would skip the
    /// rest of the "delete a call record" machinery.
    override open func anyWillRemove(with tx: SDSAnyWriteTransaction) {
        if
            let sqliteRowId,
            let associatedCallRecord = callRecordStore.fetch(
                interactionRowId: sqliteRowId, tx: tx.asV2Read
            )
        {
            callRecordStore.delete(
                callRecords: [associatedCallRecord], tx: tx.asV2Write
            )
        }
    }
}
