//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Fetches and stores names that third parties shared with us.
/// See ``AciContactShareName``.
public protocol AciContactShareNameManager {
    func fetchName(recipient: SignalRecipient, tx: DBReadTransaction) -> AciContactShareName?

    /// Stores a name for the recipient, replacing any existing one only if
    /// `allowOverwrite` is true. Names are stored stripped, and a blank name
    /// clears the stored one instead. A name that is too long for
    /// ``ProfileName`` is still stored, so that it survives a round trip
    /// through storage service.
    ///
    /// If `updateStorageService` is true and the stored name changes, the
    /// recipient is marked as needing a storage service update.
    func saveName(
        givenName: String?,
        familyName: String?,
        recipient: SignalRecipient,
        allowOverwrite: Bool,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    )

    func deleteName(recipient: SignalRecipient, updateStorageService: Bool, tx: DBWriteTransaction)
}

// MARK: -

class AciContactShareNameManagerImpl: AciContactShareNameManager {
    private let aciContactShareNameStore: AciContactShareNameStore
    private let searchableNameIndexer: any SearchableNameIndexer
    private let storageServiceManager: any StorageServiceManager

    init(
        aciContactShareNameStore: AciContactShareNameStore,
        searchableNameIndexer: any SearchableNameIndexer,
        storageServiceManager: any StorageServiceManager,
    ) {
        self.aciContactShareNameStore = aciContactShareNameStore
        self.searchableNameIndexer = searchableNameIndexer
        self.storageServiceManager = storageServiceManager
    }

    // MARK: AciContactShareNameManager

    func fetchName(recipient: SignalRecipient, tx: DBReadTransaction) -> AciContactShareName? {
        return aciContactShareNameStore.fetchOne(forRecipientRowID: recipient.id, tx: tx)
    }

    func saveName(
        givenName: String?,
        familyName: String?,
        recipient: SignalRecipient,
        allowOverwrite: Bool,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        let existingName = fetchName(recipient: recipient, tx: tx)
        if existingName != nil, !allowOverwrite {
            return
        }

        var didChangeStoredName = false
        if let existingName {
            delete(existingName, tx: tx)
            didChangeStoredName = true
        }

        let newName = AciContactShareName(recipient: recipient, givenName: givenName, familyName: familyName)
        if let newName {
            insert(newName, tx: tx)
            didChangeStoredName = true
        }

        if updateStorageService, didChangeStoredName {
            recordPendingStorageServiceUpdate(recipient: recipient, tx: tx)
        }
    }

    func deleteName(recipient: SignalRecipient, updateStorageService: Bool, tx: DBWriteTransaction) {
        guard let existingName = fetchName(recipient: recipient, tx: tx) else {
            return
        }

        delete(existingName, tx: tx)

        if updateStorageService {
            recordPendingStorageServiceUpdate(recipient: recipient, tx: tx)
        }
    }

    // MARK: -

    private func insert(_ aciContactShareName: AciContactShareName, tx: DBWriteTransaction) {
        aciContactShareNameStore.insertOne(aciContactShareName, tx: tx)
        searchableNameIndexer.insert(aciContactShareName, tx: tx)
    }

    private func delete(_ aciContactShareName: AciContactShareName, tx: DBWriteTransaction) {
        searchableNameIndexer.delete(aciContactShareName, tx: tx)
        aciContactShareNameStore.deleteOne(forRecipientRowID: aciContactShareName.recipientRowID, tx: tx)
    }

    private func recordPendingStorageServiceUpdate(recipient: SignalRecipient, tx: DBWriteTransaction) {
        let recipientUniqueId = recipient.uniqueId
        tx.addSyncCompletion { [storageServiceManager] in
            storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: [recipientUniqueId])
        }
    }
}
