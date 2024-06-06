//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC

final class CallLinkCall: Signal.GroupCall {
    init(
        ringRtcCall: SignalRingRTC.GroupCall,
        videoCaptureController: VideoCaptureController
    ) {
        super.init(
            audioDescription: "[SignalCall] Call link call",
            ringRtcCall: ringRtcCall,
            videoCaptureController: videoCaptureController
        )
    }
}
