//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class PaymentOnboarding {
    private class func ftPaymentsLockActionSheetMessage() -> String {
        switch BiometryType.biometryType {
        case .unknown:
            return OWSLocalizedString(
                "PAYMENTS_LOCK_FIRST_TIME_ACTION_SHEET_MESSAGE",
                comment: "First time payments suggest payments lock message")
        case .passcode:
            return OWSLocalizedString(
                "PAYMENTS_LOCK_FIRST_TIME_ACTION_SHEET_MESSAGE_PASSCODE",
                comment: "First time payments suggest payments lock message")
        case .faceId:
            return OWSLocalizedString(
                "PAYMENTS_LOCK_FIRST_TIME_ACTION_SHEET_MESSAGE_FACEID",
                comment: "First time payments suggest payments lock message")
        case .touchId:
            return OWSLocalizedString(
                "PAYMENTS_LOCK_FIRST_TIME_ACTION_SHEET_MESSAGE_TOUCHID",
                comment: "First time payments suggest payments lock message")
        }
    }

    private class func ftPaymentsLockAffirmativeActionTitle() -> String {
        switch BiometryType.biometryType {
        case .unknown:
            return OWSLocalizedString(
                "PAYMENTS_LOCK_FIRST_TIME_AFFIRMATIVE_ACTION",
                comment: "Affirmative action title to enable payments lock")
        case .passcode:
            return OWSLocalizedString(
                "PAYMENTS_LOCK_FIRST_TIME_AFFIRMATIVE_ACTION_PASSCODE",
                comment: "Affirmative action title to enable payments lock")
        case .faceId:
            return OWSLocalizedString(
                "PAYMENTS_LOCK_FIRST_TIME_AFFIRMATIVE_ACTION_FACEID",
                comment: "Affirmative action title to enable payments lock")
        case .touchId:
            return OWSLocalizedString(
                "PAYMENTS_LOCK_FIRST_TIME_AFFIRMATIVE_ACTION_TOUCHID",
                comment: "Affirmative action title to enable payments lock")
        }
    }

    public class func presentBiometricLockPromptIfNeeded(completion: @escaping () -> Void) {
        guard OWSPaymentsLock.shared.isTimeToShowSuggestion()
              && OWSPaymentsLock.shared.isPaymentsLockEnabled() == false
        else {
            completion()
            return
        }

        let actionSheet = ActionSheetController(title: OWSLocalizedString("PAYMENTS_LOCK_FIRST_TIME_ACTION_SHEET_TITLE",
                                                                         comment: "First time payments suggest payments lock title"),
                                                message: ftPaymentsLockActionSheetMessage())

        actionSheet.addAction(ActionSheetAction(title: ftPaymentsLockAffirmativeActionTitle(),
                                                accessibilityIdentifier: "payments.lock.first_time.affirmative_action",
                                                style: .default) { _ in
            OWSPaymentsLock.shared.setIsPaymentsLockEnabledAndSnooze(true)
            completion()
        })

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.notNowButton,
            accessibilityIdentifier: "OWSActionSheets.notNow",
            style: .cancel
        ) { _ in
            Logger.debug("Not Now")
            OWSPaymentsLock.shared.setIsPaymentsLockEnabledAndSnooze(false)
            completion()
        })

        OWSActionSheets.showActionSheet(actionSheet)
    }
}
