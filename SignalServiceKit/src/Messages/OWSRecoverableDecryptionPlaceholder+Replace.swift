//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension OWSRecoverableDecryptionPlaceholder {

    /// This method performs an upsert replacement of the placeholder with the provided interaction
    /// Callers should not continue using the placeholder after performing a replacement.
    @objc
    func replaceWithInteraction(_ interaction: TSInteraction, writeTx: SDSAnyWriteTransaction) {
        Logger.info("Replacing placeholder with recovered interaction: \(interaction.timestamp)")
        guard let inheritedId = sqliteRowId else { return owsFailDebug("Missing rowId") }

        interaction.replaceRowId(inheritedId, uniqueId: uniqueId)
        interaction.replaceSortId(UInt64(inheritedId))

        interaction.anyOverwritingUpdate(transaction: writeTx)
    }
}
