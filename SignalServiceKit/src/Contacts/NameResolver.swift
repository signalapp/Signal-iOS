//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
    func displayName(for address: SignalServiceAddress, tx: DBReadTransaction) -> DisplayName
}

public class NameResolverImpl: NameResolver {
    private let contactsManager: any ContactManager

    private var displayNameCache = [SignalServiceAddress: DisplayName]()

    public init(contactsManager: any ContactManager) {
        self.contactsManager = contactsManager
    }

    private func cachedValue(
        for address: SignalServiceAddress,
        orValue value: @autoclosure () -> DisplayName
    ) -> DisplayName {
        if let cachedResult = displayNameCache[address] {
            return cachedResult
        }
        let result = value()
        displayNameCache[address] = result
        return result
    }

    public func displayName(for address: SignalServiceAddress, tx: DBReadTransaction) -> DisplayName {
        let tx = SDSDB.shimOnlyBridge(tx)
        checkTransaction(transaction: tx)
        return cachedValue(
            for: address,
            orValue: contactsManager.displayName(for: address, tx: tx)
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
