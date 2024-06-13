//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC

final class CallLinkCall: Signal.GroupCall {
    let callLink: CallLink

    init(
        callLink: CallLink,
        ringRtcCall: SignalRingRTC.GroupCall,
        videoCaptureController: VideoCaptureController
    ) {
        self.callLink = callLink
        super.init(
            audioDescription: "[SignalCall] Call link call",
            ringRtcCall: ringRtcCall,
            videoCaptureController: videoCaptureController
        )
    }
}
