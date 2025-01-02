//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class MessageBackupRecipientStore {

    private let recipientTable: RecipientDatabaseTable
    private let searchableNameIndexer: SearchableNameIndexer

    init(
        recipientTable: RecipientDatabaseTable,
        searchableNameIndexer: SearchableNameIndexer
    ) {
        self.recipientTable = recipientTable
        self.searchableNameIndexer = searchableNameIndexer
    }

    // MARK: - Archiving

    func enumerateAllSignalRecipients(
        _ context: MessageBackup.RecipientArchivingContext,
        block: (SignalRecipient) -> Void
    ) throws {
        let cursor = try SignalRecipient.fetchCursor(context.tx.databaseConnection)
        while let next = try cursor.next() {
            try Task.checkCancellation()
            block(next)
        }
    }

    func fetchRecipient(
        for address: MessageBackup.ContactAddress,
        context: MessageBackup.RecipientArchivingContext
    ) -> SignalRecipient? {
        return recipientTable.fetchRecipient(address: address.asInteropAddress(), tx: context.tx)
    }

    // MARK: - Restoring

    func insertRecipient(
        _ recipient: SignalRecipient,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        try recipient.insert(context.tx.databaseConnection)
        // Unlike messages, whose indexing is deferred, we insert
        // into the index immediately within the backup write tx.
        // This is because:
        // 1. There are way fewer recipients than messages
        // 2. Its not unlikely one of the first things the user
        //    will do post-restore is search up a recipient.
        // If this ends up being a performance issue, we can
        // defer this indexing, too.
        searchableNameIndexer.insert(recipient, tx: context.tx)
    }
}
