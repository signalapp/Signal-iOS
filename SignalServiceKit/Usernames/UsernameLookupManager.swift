//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An interface for fetching and storing usernames. Note that with the
/// exception of the local user, any stored data about an account's username is
/// only as fresh as the last time we looked it up - usernames should be
/// considered transient.
public protocol UsernameLookupManager {
    typealias Username = String

    /// Fetch the most recently-known username for the given ACI, if any.
    func fetchUsername(
        forAci aci: UntypedServiceId,
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
        forAci aci: UntypedServiceId,
        transaction: DBWriteTransaction
    )
}

/// A ``UsernameLookupManager`` implementation that uses on-disk persistence
/// paired with an in-memory cache.
class UsernameLookupManagerImpl: UsernameLookupManager {

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

    private let cachedLookups: AtomicDictionary<UntypedServiceId, CachedLookupResult>

    init() {
        cachedLookups = .init(lock: .init())
    }

    // MARK: - UsernameLookupManager

    func fetchUsername(
        forAci aci: UntypedServiceId,
        transaction: DBReadTransaction
    ) -> Username? {
        if let cachedLookup = cachedLookups[aci] {
            return cachedLookup.usernameValue
        }

        if let persistedUsername = UsernameLookupRecord.fetchOne(
            forAci: aci,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )?.username {
            cachedLookups[aci] = .found(username: persistedUsername)
            return persistedUsername
        }

        cachedLookups[aci] = .notFound
        return nil
    }

    func fetchUsernames(
        forAddresses addresses: AnySequence<SignalServiceAddress>,
        transaction: DBReadTransaction
    ) -> [Username?] {
        addresses.map { address -> Username? in
            guard let aci = address.untypedServiceId else { return nil }

            return fetchUsername(forAci: aci, transaction: transaction)
        }
    }

    func saveUsername(
        _ username: Username?,
        forAci aci: UntypedServiceId,
        transaction: DBWriteTransaction
    ) {
        if let username {
            cachedLookups[aci] = .found(username: username)

            UsernameLookupRecord(aci: aci, username: username)
                .upsert(transaction: SDSDB.shimOnlyBridge(transaction))
        } else {
            cachedLookups[aci] = .notFound

            UsernameLookupRecord.deleteOne(
                forAci: aci,
                transaction: SDSDB.shimOnlyBridge(transaction)
            )
        }
    }
}
