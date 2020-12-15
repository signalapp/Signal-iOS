//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

extension TSInteraction {

    @objc
    public func ensureSortIdForInsertedInteraction(transaction: SDSAnyReadTransaction) {
        switch transaction.readTransaction {
        case .yapRead:
            owsFailDebug("Unexpected transaction.")
            return
        case .grdbRead(let grdbRead):
            ensureSortIdForInsertedInteraction(transaction: grdbRead)
        }
    }

    private func ensureSortIdForInsertedInteraction(transaction: GRDBReadTransaction) {
        guard self.sortId == 0 else {
            owsFailDebug("Unexpected sortId: \(sortId).")
            return
        }
        guard let sortId = BaseModel.grdbIdByUniqueId(tableMetadata: TSInteractionSerializer.table,
                                                      uniqueIdColumnName: InteractionRecord.columnName(.uniqueId),
                                                      uniqueIdColumnValue: self.uniqueId,
                                                      transaction: transaction) else {
            owsFailDebug("Missing sortId.")
            return
        }
        guard sortId > 0, sortId <= UInt64.max else {
            owsFailDebug("Invalid sortId: \(sortId).")
            return
        }
        self.replaceSortId(UInt64(sortId))
        owsAssertDebug(self.sortId > 0)
    }
}
