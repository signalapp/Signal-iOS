//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension OWSGroupCallMessage {
    /// Explicitly delete any ``CallRecord`` associated with this interaction.
    ///
    /// These records would be deleted automatically due to their foreign key
    /// reference to this interaction, but that auto-deletion would skip the
    /// rest of the "delete a call record" machinery.
    override open func anyWillRemove(with tx: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.callRecordDeleteManager.deleteCallRecord(
            associatedGroupCallInteraction: self,
            tx: tx.asV2Write
        )
    }
}
