//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

class MockUsernameLookupManager: UsernameLookupManager {
    typealias Username = String

    private var mockUsernames: [Aci: Username] = [:]

    init() {}

    func clearAllUsernames() {
        mockUsernames.removeAll()
    }

    // MARK: - UsernameLookupManager

    func fetchUsername(forAci aci: Aci, transaction: DBReadTransaction) -> Username? {
        mockUsernames[aci]
    }

    func fetchUsernames(forAddresses addresses: AnySequence<SignalServiceAddress>, transaction: DBReadTransaction) -> [Username?] {
        addresses.map { address -> Username? in
            guard let aci = address.serviceId as? Aci else { return nil }

            return fetchUsername(forAci: aci, transaction: transaction)
        }
    }

    func saveUsername(_ username: Username?, forAci aci: Aci, transaction: DBWriteTransaction) {
        mockUsernames[aci] = username
    }
}
