//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public enum ContactSupportRegistrationPINMode: String, Equatable {
    case v1 = "Signal PIN - iOS (V1 PIN)"
    case v2NoReglock = "Signal PIN - iOS (V2 PIN without RegLock)"
    case v2WithReglock = "Signal PIN - iOS (V2 PIN)"
    case v2WithUnknownReglockState = "Signal PIN - iOS (V2 PIN with unknown reglock)"
}

extension ContactSupportAlert {

    static func showForRegistrationPINMode(
        _ mode: ContactSupportRegistrationPINMode,
        from vc: UIViewController
    ) {
        Logger.info("")
        ContactSupportAlert.presentStep2(
            emailSupportFilter: mode.rawValue,
            fromViewController: vc
        )
    }
}
