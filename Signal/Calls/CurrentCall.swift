//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

struct CurrentCall {
    private let rawValue: AtomicValue<SignalCall?>

    init(rawValue: AtomicValue<SignalCall?>) {
        self.rawValue = rawValue
    }

    func get() -> SignalCall? { rawValue.get() }
}

extension CurrentCall: CurrentCallProvider {
    var hasCurrentCall: Bool { self.get() != nil }
    var currentGroupThreadCallGroupId: GroupIdentifier? {
        switch self.get()?.mode {
        case nil, .individual, .callLink:
            return nil
        case .groupThread(let call):
            return call.groupId
        }
    }
}
