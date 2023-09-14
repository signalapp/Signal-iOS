//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

class AuthorMergeObserver: RecipientMergeObserver {
    func willBreakAssociation(for recipient: SignalRecipient, tx: DBWriteTransaction) {
        guard let aciString = recipient.aciString, let phoneNumber = recipient.phoneNumber else {
            // We don't receive messages from PNIs, so we don't need to consider the
            // PNI in this method. If this changes in the future, we still won't need
            // to do this because we'd never save an incoming message from a phone
            // number that needs to be changed to a PNI. (This is similar to how all
            // incoming messages have an ACI so newly-added messages *also* don't need
            // to be run through this logic.)
            return
        }
        populateMissingAcis(phoneNumber: phoneNumber, aciString: aciString, tx: tx)
    }

    func didLearnAssociation(mergedRecipient: MergedRecipient, transaction: DBWriteTransaction) {
        // As an performance optimization, don't assign missing ACIs unless we
        // must. When we learn an association, we don't need to assign ACIs because
        // we can still fetch based on phone number. When we *break* an
        // association, we must populate missing values because we'll no longer be
        // able to fetch based on the phone number.
    }

    private func populateMissingAcis(phoneNumber: String, aciString: String, tx: DBWriteTransaction) {
        for table in AuthorDatabaseTable.all {
            let sql = """
                UPDATE "\(table.name)"
                SET "\(table.aciColumn)" = ?
                WHERE "\(table.phoneNumberColumn)" = ?
                AND "\(table.aciColumn)" IS NULL
            """
            let arguments: StatementArguments = [aciString, phoneNumber]
            SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.execute(sql: sql, arguments: arguments)
        }
        ModelReadCaches.shared.evacuateAllCaches()
    }
}

private struct AuthorDatabaseTable {
    let name: String
    let aciColumn: String
    let phoneNumberColumn: String

    static var all: [AuthorDatabaseTable] {
        return [
            AuthorDatabaseTable(
                name: OWSReaction.databaseTableName,
                aciColumn: OWSReaction.columnName(.reactorUUID),
                phoneNumberColumn: OWSReaction.columnName(.reactorE164)
            ),
            AuthorDatabaseTable(
                name: InteractionRecord.databaseTableName,
                aciColumn: InteractionRecord.columnName(.authorUUID),
                phoneNumberColumn: InteractionRecord.columnName(.authorPhoneNumber)
            ),
            AuthorDatabaseTable(
                name: "pending_read_receipts",
                aciColumn: "authorUuid",
                phoneNumberColumn: "authorPhoneNumber"
            ),
            AuthorDatabaseTable(
                name: "pending_viewed_receipts",
                aciColumn: "authorUuid",
                phoneNumberColumn: "authorPhoneNumber"
            )
        ]
    }
}
