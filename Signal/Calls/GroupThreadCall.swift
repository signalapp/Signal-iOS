//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit

class GroupThreadCall {
    let ringRtcCall: SignalRingRTC.GroupCall
    let groupThread: TSGroupThread

    init(ringRtcCall: SignalRingRTC.GroupCall, groupThread: TSGroupThread) {
        self.ringRtcCall = ringRtcCall
        self.groupThread = groupThread
    }
}
