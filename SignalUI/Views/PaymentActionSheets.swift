//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class PaymentActionSheets {
    public static func showBiometryAuthFailedActionSheet(_ handler: ActionSheetAction.Handler? = nil) {
        let title = OWSLocalizedString(
            "PAYMENTS_LOCK_LOCAL_BIOMETRY_AUTH_DISABLED_TITLE",
            comment: "Title for action sheet shown when unlocking with biometrics like Face ID or TouchID fails because it is disabled at a system level.")
        let message = OWSLocalizedString(
            "PAYMENTS_LOCK_LOCAL_BIOMETRY_AUTH_DISABLED_MESSAGE",
            comment: "Message for action sheet shown when unlocking with biometrics like Face ID or TouchID fails because it is disabled at a system level.")

        OWSActionSheets.showActionSheet(
            title: title,
            message: message,
            buttonTitle: CommonStrings.okButton,
            buttonAction: handler
        )
    }
}
