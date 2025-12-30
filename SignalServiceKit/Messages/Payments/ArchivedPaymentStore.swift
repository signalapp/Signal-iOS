//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct ArchivedPaymentStore {
    public func enumerateAll(
        tx: DBReadTransaction,
        block: @escaping (ArchivedPayment, _ stop: inout Bool) -> Void,
    ) {
        failIfThrows {
            let cursor = try ArchivedPayment.fetchCursor(tx.database)
            var stop = false
            while let archivedPayment = try cursor.next() {
                block(archivedPayment, &stop)
                if stop {
                    break
                }
            }
        }
    }

    public func fetch(
        for archivedPaymentMessage: OWSArchivedPaymentMessage,
        interactionUniqueId: String,
        tx: DBReadTransaction,
    ) -> ArchivedPayment? {
        failIfThrows {
            return try ArchivedPayment
                .filter(Column(ArchivedPayment.CodingKeys.interactionUniqueId) == interactionUniqueId)
                .fetchOne(tx.database)
        }
    }

    public func insert(_ archivedPayment: ArchivedPayment, tx: DBWriteTransaction) {
        failIfThrows {
            try archivedPayment.insert(tx.database)
        }
    }
}
