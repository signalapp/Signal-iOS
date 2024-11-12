//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol ArchivedPaymentStore {
    func insert(_ archivedPayment: ArchivedPayment, tx: DBWriteTransaction) throws
    func fetch(
        for archivedPaymentMessage: OWSArchivedPaymentMessage,
        interactionUniqueId: String,
        tx: DBReadTransaction
    ) throws -> ArchivedPayment?
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

    public func fetch(
        for archivedPaymentMessage: OWSArchivedPaymentMessage,
        interactionUniqueId: String,
        tx: DBReadTransaction
    ) throws -> ArchivedPayment? {
        do {
            return try ArchivedPayment
                .filter(Column(ArchivedPayment.CodingKeys.interactionUniqueId) == interactionUniqueId)
                .fetchOne(tx.databaseConnection)
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            throw error
        }
    }

    public func insert(_ archivedPayment: ArchivedPayment, tx: DBWriteTransaction) throws {
        try archivedPayment.insert(tx.databaseConnection)
    }
}
