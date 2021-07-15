//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

extension OWSRecoverableDecryptionPlaceholder {
    @objc
    func replaceWithInteraction(_ interaction: TSInteraction, writeTx: SDSAnyWriteTransaction) {
        guard let inheritedId = grdbId?.int64Value else { return owsFailDebug("Missing rowId") }

        interaction.anyInsert(transaction: writeTx)
        anyRemove(transaction: writeTx)

        interaction.clearRowId()
        interaction.updateRowId(inheritedId)
        interaction.anyOverwritingUpdate(transaction: writeTx)
    }
}
