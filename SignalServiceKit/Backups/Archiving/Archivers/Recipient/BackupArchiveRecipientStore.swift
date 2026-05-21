//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public class BackupArchiveRecipientStore {

    private let recipientTable: RecipientDatabaseTable
    private let searchableNameIndexer: SearchableNameIndexer

    init(
        recipientTable: RecipientDatabaseTable,
        searchableNameIndexer: SearchableNameIndexer,
    ) {
        self.recipientTable = recipientTable
        self.searchableNameIndexer = searchableNameIndexer
    }

    // MARK: - Archiving

    func enumerateAllSignalRecipients(
        tx: DBReadTransaction,
        block: (SignalRecipient) throws(CancellationError) -> Bool,
    ) throws(CancellationError) {
        var cursor = FailIfThrowsRecordCursor {
            try SignalRecipient.fetchCursor(tx.database)
        }

        while let recipient = cursor.next(), try block(recipient) {}
    }

    func fetchRecipient(
        for address: BackupArchive.ContactAddress,
        tx: DBReadTransaction,
    ) -> SignalRecipient? {
        return recipientTable.fetchRecipient(address: address.asInteropAddress(), tx: tx)
    }

    func fetchRecipient(
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) -> SignalRecipient? {
        return recipientTable.fetchRecipient(serviceId: localIdentifiers.aci, transaction: tx)
    }

    // MARK: - Restoring

    func didInsertRecipient(_ recipient: SignalRecipient, tx: DBWriteTransaction) {
        // Unlike messages, whose indexing is deferred, we insert
        // into the index immediately within the backup write tx.
        // This is because:
        // 1. There are way fewer recipients than messages
        // 2. Its not unlikely one of the first things the user
        //    will do post-restore is search up a recipient.
        // If this ends up being a performance issue, we can
        // defer this indexing, too.
        searchableNameIndexer.insert(recipient, tx: tx)
    }
}
