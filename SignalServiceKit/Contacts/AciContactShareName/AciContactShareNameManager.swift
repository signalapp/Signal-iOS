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

    init(aciContactShareNameStore: AciContactShareNameStore) {
        self.aciContactShareNameStore = aciContactShareNameStore
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
        }
    }

    func deleteName(for recipient: SignalRecipient, tx: DBWriteTransaction) {
        aciContactShareNameStore.deleteOne(forRecipientRowID: recipient.id, tx: tx)
    }
}
