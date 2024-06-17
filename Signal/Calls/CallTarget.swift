//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum CallTarget {
    case individual(TSContactThread)
    case groupThread(TSGroupThread)
    case callLink(CallLink)
}

extension TSContactThread {
    var canCall: Bool {
        return !isNoteToSelf
    }
}

extension TSGroupThread {
    var canCall: Bool {
        return (
            isGroupV2Thread
            && groupMembership.isLocalUserFullMember
        )
    }
}
