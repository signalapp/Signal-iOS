//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class MockUsernameLookupManager: UsernameLookupManager {

    private var mockUsernames: [ACI: Username] = [:]

    init() {}

    func clearAllUsernames() {
        mockUsernames.removeAll()
    }

    // MARK: - UsernameLookupManager

    func fetchUsername(forAci aci: ACI, transaction: DBReadTransaction) -> Username? {
        mockUsernames[aci]
    }

    func fetchUsernames(forAddresses addresses: AnySequence<SignalServiceAddress>, transaction: DBReadTransaction) -> [Username?] {
        addresses.map { address -> Username? in
            guard let aci = address.uuid else { return nil }

            return fetchUsername(forAci: aci, transaction: transaction)
        }
    }

    func saveUsername(_ username: Username, forAci aci: ACI, transaction: DBWriteTransaction) {
        mockUsernames[aci] = username
    }

    func clearUsername(forAci aci: ACI, transaction: DBWriteTransaction) {
        mockUsernames.removeValue(forKey: aci)
    }
}
