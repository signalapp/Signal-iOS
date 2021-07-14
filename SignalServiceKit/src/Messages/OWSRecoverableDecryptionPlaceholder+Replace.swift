//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

extension OWSRecoverableDecryptionPlaceholder {
    @objc
    func replaceWithInteraction(_ interaction: TSInteraction, writeTx: SDSAnyWriteTransaction) {
        anyRemove(transaction: writeTx)

        if let inheritedId = grdbId?.int64Value {
            interaction.clearRowId()
            interaction.updateRowId(inheritedId)
        } else {
            owsFailDebug("Missing rowId")
        }
        anyInsert(transaction: writeTx)
    }
}
