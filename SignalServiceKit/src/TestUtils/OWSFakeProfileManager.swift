//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

extension OWSFakeProfileManager: ProfileManager {
    public func fullNames(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [String?] {
        if let fakeDisplayNames {
            return addresses.map { fakeDisplayNames[$0] }
        } else {
            return Array(repeating: "some fake profile name", count: addresses.count)
        }
    }
}

#endif
