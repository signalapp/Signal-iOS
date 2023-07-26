//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class MockUsernameLookupManager: UsernameLookupManager {

    private var mockUsernames: [UntypedServiceId: Username] = [:]

    init() {}

    func clearAllUsernames() {
        mockUsernames.removeAll()
    }

    // MARK: - UsernameLookupManager

    func fetchUsername(forAci aci: UntypedServiceId, transaction: DBReadTransaction) -> Username? {
        mockUsernames[aci]
    }

    func fetchUsernames(forAddresses addresses: AnySequence<SignalServiceAddress>, transaction: DBReadTransaction) -> [Username?] {
        addresses.map { address -> Username? in
            guard let aci = address.untypedServiceId else { return nil }

            return fetchUsername(forAci: aci, transaction: transaction)
        }
    }

    func saveUsername(_ username: Username?, forAci aci: UntypedServiceId, transaction: DBWriteTransaction) {
        mockUsernames[aci] = username
    }
}
