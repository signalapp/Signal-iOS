//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
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

    var localizedName: String {
        return self.callLinkState.name ?? Self.defaultLocalizedName
    }

    static var defaultLocalizedName: String {
        return OWSLocalizedString(
            "SIGNAL_CALL",
            comment: "Shown in the header when the user hasn't provided a custom name for a call."
        )
    }
}
