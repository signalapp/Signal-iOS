//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// An interface for fetching and storing usernames. Note that with the
/// exception of the local user, any stored data about an account's username is
/// only as fresh as the last time we looked it up - usernames should be
/// considered transient.
public protocol UsernameLookupManager {
    typealias Username = String

    /// Fetch the most recently-known username for the given ACI, if any.
    func fetchUsername(
        forAci aci: Aci,
        transaction: DBReadTransaction
    ) -> Username?

    /// Fetch usernames for the given addresses, returning an array with a
    /// username corresponding to each passed address, if one is available.
    func fetchUsernames(
        forAddresses addresses: AnySequence<SignalServiceAddress>,
        transaction: DBReadTransaction
    ) -> [Username?]

    /// Save the given username, or lack thereof, for the given ACI.
    func saveUsername(
        _ username: Username?,
        forAci aci: Aci,
        transaction: DBWriteTransaction
    )
}

/// A ``UsernameLookupManager`` implementation that uses on-disk persistence
/// paired with an in-memory cache.
final public class UsernameLookupManagerImpl: UsernameLookupManager {
    public typealias Username = String

    private enum CachedLookupResult {
        case found(username: Username)
        case notFound

        var usernameValue: Username? {
            switch self {
            case let .found(username):
                return username
            case .notFound:
                return nil
            }
        }
    }

    // MARK: - Init

    private let cachedLookups: AtomicDictionary<Aci, CachedLookupResult>
    private let searchableNameIndexer: any SearchableNameIndexer
    private let usernameLookupRecordStore: any UsernameLookupRecordStore

    public init(
        searchableNameIndexer: any SearchableNameIndexer,
        usernameLookupRecordStore: any UsernameLookupRecordStore
    ) {
        self.cachedLookups = .init(lock: .init())
        self.searchableNameIndexer = searchableNameIndexer
        self.usernameLookupRecordStore = usernameLookupRecordStore
    }

    // MARK: - UsernameLookupManager

    public func fetchUsername(
        forAci aci: Aci,
        transaction: DBReadTransaction
    ) -> Username? {
        if let cachedLookup = cachedLookups[aci] {
            return cachedLookup.usernameValue
        }

        let persistedUsername = usernameLookupRecordStore.fetchOne(forAci: aci, tx: transaction)?.username
        if let persistedUsername {
            cachedLookups[aci] = .found(username: persistedUsername)
            return persistedUsername
        }

        cachedLookups[aci] = .notFound
        return nil
    }

    public func fetchUsernames(
        forAddresses addresses: AnySequence<SignalServiceAddress>,
        transaction: DBReadTransaction
    ) -> [Username?] {
        addresses.map { address -> Username? in
            guard let aci = address.serviceId as? Aci else { return nil }

            return fetchUsername(forAci: aci, transaction: transaction)
        }
    }

    public func saveUsername(
        _ username: Username?,
        forAci aci: Aci,
        transaction tx: DBWriteTransaction
    ) {
        // Delete first to ensure we can index the new value in FTS.
        usernameLookupRecordStore.deleteOne(forAci: aci, tx: tx)

        if let username {
            cachedLookups[aci] = .found(username: username)
            let usernameLookupRecord = UsernameLookupRecord(aci: aci, username: username)
            usernameLookupRecordStore.insertOne(usernameLookupRecord, tx: tx)
            searchableNameIndexer.insert(usernameLookupRecord, tx: tx)
        } else {
            cachedLookups[aci] = .notFound
        }
    }
}
