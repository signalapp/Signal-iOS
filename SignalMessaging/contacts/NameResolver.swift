//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// A transaction-scoped, address-to-user-visible-name resolver.
///
/// This class is a cache for user-visible names. If you need to look up the
/// name associated with an address multiple times, you may see a
/// performance improvement from adopting this class.
///
/// An instance of this class is only valid within the context of a single
/// transaction. If your transaction ends, the names might change before the
/// next transaction starts, so you need to throw away the cached state and
/// re-fetch it from disk. In debug builds, this class will ensure that it's
/// always used with the same transaction object.
public protocol NameResolver {
    func displayName(
        for address: SignalServiceAddress,
        useShortNameIfAvailable: Bool,
        transaction: DBReadTransaction
    ) -> String

    func comparableName(
        for address: SignalServiceAddress,
        transaction: DBReadTransaction
    ) -> String
}

public class NameResolverImpl: NameResolver {
    private let contactsManager: ContactsManagerProtocol

    private var displayNameCache = [SignalServiceAddress: String]()
    private var shortDisplayNameCache = [SignalServiceAddress: String]()
    private var comparableNameCache = [SignalServiceAddress: String]()

    public init(contactsManager: ContactsManagerProtocol) {
        self.contactsManager = contactsManager
    }

    private func cachedValue(
        for address: SignalServiceAddress,
        in cache: inout [SignalServiceAddress: String],
        orValue value: @autoclosure () -> String
    ) -> String {
        if let cachedResult = cache[address] {
            return cachedResult
        }
        let result = value()
        cache[address] = result
        return result
    }

    public func displayName(
        for address: SignalServiceAddress,
        useShortNameIfAvailable: Bool,
        transaction: DBReadTransaction
    ) -> String {
        let transaction = SDSDB.shimOnlyBridge(transaction)
        checkTransaction(transaction: transaction)
        if useShortNameIfAvailable {
            return cachedValue(
                for: address,
                in: &shortDisplayNameCache,
                orValue: contactsManager.shortDisplayName(for: address, transaction: transaction)
            )
        } else {
            return cachedValue(
                for: address,
                in: &displayNameCache,
                orValue: contactsManager.displayName(for: address, transaction: transaction)
            )
        }
    }

    public func comparableName(for address: SignalServiceAddress, transaction: DBReadTransaction) -> String {
        let transaction = SDSDB.shimOnlyBridge(transaction)
        checkTransaction(transaction: transaction)
        return cachedValue(
            for: address,
            in: &comparableNameCache,
            orValue: contactsManager.comparableName(for: address, transaction: transaction)
        )
    }

#if DEBUG
    private weak var expectedTransaction: SDSAnyReadTransaction?
#endif

    private func checkTransaction(transaction: SDSAnyReadTransaction) {
#if DEBUG
        if expectedTransaction == nil {
            expectedTransaction = transaction
        }
        assert(expectedTransaction == transaction)
#endif
    }
}
