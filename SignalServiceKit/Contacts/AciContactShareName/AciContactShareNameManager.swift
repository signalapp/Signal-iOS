//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Fetches and stores names that third parties shared with us.
/// See ``AciContactShareName``.
public protocol AciContactShareNameManager {
    func fetchName(for recipient: SignalRecipient, tx: DBReadTransaction) -> AciContactShareName?

    /// Replaces any name stored for the recipient. Names are stored stripped,
    /// and a blank name clears the stored one instead. A name that is too long
    /// for ``ProfileName`` is still stored, so that it survives a round trip
    /// through storage service.
    func saveName(
        givenName: String?,
        familyName: String?,
        for recipient: SignalRecipient,
        tx: DBWriteTransaction,
    )

    func deleteName(for recipient: SignalRecipient, tx: DBWriteTransaction)
}

// MARK: -

class AciContactShareNameManagerImpl: AciContactShareNameManager {
    private let aciContactShareNameStore: AciContactShareNameStore
    private let searchableNameIndexer: any SearchableNameIndexer

    init(
        aciContactShareNameStore: AciContactShareNameStore,
        searchableNameIndexer: any SearchableNameIndexer,
    ) {
        self.aciContactShareNameStore = aciContactShareNameStore
        self.searchableNameIndexer = searchableNameIndexer
    }

    // MARK: AciContactShareNameManager

    func fetchName(for recipient: SignalRecipient, tx: DBReadTransaction) -> AciContactShareName? {
        return aciContactShareNameStore.fetchOne(forRecipientRowID: recipient.id, tx: tx)
    }

    func saveName(
        givenName: String?,
        familyName: String?,
        for recipient: SignalRecipient,
        tx: DBWriteTransaction,
    ) {
        deleteName(for: recipient, tx: tx)

        if let aciContactShareName = AciContactShareName(recipient: recipient, givenName: givenName, familyName: familyName) {
            aciContactShareNameStore.insertOne(aciContactShareName, tx: tx)
            searchableNameIndexer.insert(aciContactShareName, tx: tx)
        }
    }

    func deleteName(for recipient: SignalRecipient, tx: DBWriteTransaction) {
        guard let aciContactShareName = aciContactShareNameStore.fetchOne(forRecipientRowID: recipient.id, tx: tx) else {
            return
        }

        searchableNameIndexer.delete(aciContactShareName, tx: tx)
        aciContactShareNameStore.deleteOne(forRecipientRowID: recipient.id, tx: tx)
    }
}
