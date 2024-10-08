//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol ArchivedPaymentStore {
    func insert(_ archivedPayment: ArchivedPayment, tx: DBWriteTransaction)
    func fetch(for archivedPaymentMessage: OWSArchivedPaymentMessage, tx: DBReadTransaction) -> ArchivedPayment?
    func enumerateAll(tx: DBReadTransaction, block: @escaping (ArchivedPayment, _ stop: inout Bool) -> Void)
}

public struct ArchivedPaymentStoreImpl: ArchivedPaymentStore {
    public func enumerateAll(
        tx: DBReadTransaction,
        block: @escaping (ArchivedPayment, _ stop: inout Bool) -> Void
    ) {
        do {
            let cursor = try ArchivedPayment.fetchCursor(tx.databaseConnection)
            var stop = false
            while let archivedPayment = try cursor.next() {
                block(archivedPayment, &stop)
                if stop {
                    break
                }
            }
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Missing instance.")
        }
    }

    public func fetch(for archivedPaymentMessage: OWSArchivedPaymentMessage, tx: DBReadTransaction) -> ArchivedPayment? {
        let db = tx.databaseConnection
        guard let interaction = archivedPaymentMessage as? TSInteraction else {
            owsFailDebug("Unexpected message type passed to archive payment fetch.")
            return nil
        }
        do {
            return try ArchivedPayment
                .filter(Column(ArchivedPayment.CodingKeys.interactionUniqueId) == interaction.uniqueId)
                .fetchOne(db)
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Missing instance.")
        }
    }

    public func insert(_ archivedPayment: ArchivedPayment, tx: DBWriteTransaction) {
        do {
            try archivedPayment.insert(tx.databaseConnection)
        } catch {
            owsFailDebug("Unexpected payment history insertion error \(error)")
        }
    }
}
