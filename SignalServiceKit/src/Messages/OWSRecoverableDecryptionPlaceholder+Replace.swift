//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

extension OWSRecoverableDecryptionPlaceholder {

    /// This method performs an upsert replacement of the placeholder with the provided interaction
    /// Callers should not continue using the placeholder after performing a replacement.
    @objc
    func replaceWithInteraction(_ interaction: TSInteraction, writeTx: SDSAnyWriteTransaction) {
        Logger.info("Replacing placeholder with recovered interaction: \(interaction.timestamp)")
        guard let inheritedId = grdbId?.int64Value else { return owsFailDebug("Missing rowId") }
        interaction.replaceRowId(inheritedId, uniqueId: uniqueId)

        interaction.anyOverwritingUpdate(transaction: writeTx)
    }
}
