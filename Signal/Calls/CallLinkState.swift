//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC

struct CallLinkState {
    let name: String?
    let requiresAdminApproval: Bool

    init(_ rawValue: SignalRingRTC.CallLinkState) {
        self.name = rawValue.name.nilIfEmpty
        self.requiresAdminApproval = {
            switch rawValue.restrictions {
            case .adminApproval: return true
            case .none, .unknown: return false
            }
        }()
    }
}
