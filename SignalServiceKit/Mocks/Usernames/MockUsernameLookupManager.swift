//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
public import LibSignalClient

final public class MockUsernameLookupManager: UsernameLookupManager {
    public typealias Username = String

    private var mockUsernames: [Aci: Username] = [:]

    func clearAllUsernames() {
        mockUsernames.removeAll()
    }

    // MARK: UsernameLookupManager

    public func fetchUsername(forAci aci: Aci, transaction: DBReadTransaction) -> Username? {
        mockUsernames[aci]
    }

    public func fetchUsernames(forAddresses addresses: AnySequence<SignalServiceAddress>, transaction: DBReadTransaction) -> [Username?] {
        addresses.map { address -> Username? in
            guard let aci = address.serviceId as? Aci else { return nil }

            return fetchUsername(forAci: aci, transaction: transaction)
        }
    }

    public func saveUsername(_ username: Username?, forAci aci: Aci, transaction: DBWriteTransaction) {
        mockUsernames[aci] = username
    }
}

#endif
