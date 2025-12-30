//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
public import LibSignalClient

/// An interface for fetching and storing usernames. Note that with the
/// exception of the local user, any stored data about an account's username is
/// only as fresh as the last time we looked it up - usernames should be
/// considered transient.
public protocol UsernameLookupManager {
    /// Fetch the most recently-known username for the given ACI, if any.
    func fetchUsername(
        forAci aci: Aci,
        transaction: DBReadTransaction,
    ) -> String?

    /// Fetch usernames for the given addresses, returning an array with a
    /// username corresponding to each passed address, if one is available.
    func fetchUsernames(
        forAddresses addresses: AnySequence<SignalServiceAddress>,
        transaction: DBReadTransaction,
    ) -> [String?]

    /// Save the given username, or lack thereof, for the given ACI.
    func saveUsername(
        _ username: String?,
        forAci aci: Aci,
        transaction: DBWriteTransaction,
    )
}

// MARK: -

class UsernameLookupManagerImpl: UsernameLookupManager {
    private let searchableNameIndexer: any SearchableNameIndexer
    private let usernameLookupRecordStore: UsernameLookupRecordStore

    init(
        searchableNameIndexer: SearchableNameIndexer,
        usernameLookupRecordStore: UsernameLookupRecordStore,
    ) {
        self.searchableNameIndexer = searchableNameIndexer
        self.usernameLookupRecordStore = usernameLookupRecordStore
    }

    // MARK: -

    func fetchUsername(
        forAci aci: Aci,
        transaction tx: DBReadTransaction,
    ) -> String? {
        return usernameLookupRecordStore.fetchOne(forAci: aci, tx: tx)?.username
    }

    func fetchUsernames(
        forAddresses addresses: some Sequence<SignalServiceAddress>,
        transaction tx: DBReadTransaction,
    ) -> [String?] {
        return addresses.map { address -> String? in
            guard let aci = address.aci else { return nil }
            return fetchUsername(forAci: aci, transaction: tx)
        }
    }

    // MARK: -

    func saveUsername(
        _ username: String?,
        forAci aci: Aci,
        transaction tx: DBWriteTransaction,
    ) {
        // First, delete any existing records for this ACI. This ensures that we
        // can, if we insert a new record, subsequently index the new username
        // in FTS via SearchableName.
        usernameLookupRecordStore.deleteOne(forAci: aci, tx: tx)

        if let username {
            // The `username` column is UNIQUE (enforced by an index), so we
            // must take care to wipe any previous associations for this
            // username (case-insensitive).
            //
            // This is semantically appropriate as usernames can only be
            // associated with one ACI at a time.
            if
                let conflictingRecord = usernameLookupRecordStore.fetchOne(
                    forUsernameCaseInsensitive: username,
                    tx: tx,
                )
            {
                let conflictingAci = Aci(fromUUID: conflictingRecord.aci)
                usernameLookupRecordStore.deleteOne(forAci: conflictingAci, tx: tx)
            }

            let usernameLookupRecord = UsernameLookupRecord(aci: aci, username: username)
            usernameLookupRecordStore.insertOne(usernameLookupRecord, tx: tx)
            searchableNameIndexer.insert(usernameLookupRecord, tx: tx)
        }
    }
}
