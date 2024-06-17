//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC

final class CallLinkCall: Signal.GroupCall {
    let callLink: CallLink
    let adminPasskey: Data?
    let callLinkState: CallLinkState

    init(
        callLink: CallLink,
        adminPasskey: Data?,
        callLinkState: CallLinkState,
        ringRtcCall: SignalRingRTC.GroupCall,
        videoCaptureController: VideoCaptureController
    ) {
        self.callLink = callLink
        self.adminPasskey = adminPasskey
        self.callLinkState = callLinkState
        super.init(
            audioDescription: "[SignalCall] Call link call",
            ringRtcCall: ringRtcCall,
            videoCaptureController: videoCaptureController
        )
    }

    var mayNeedToAskToJoin: Bool {
        return callLinkState.requiresAdminApproval && adminPasskey == nil
    }
}
