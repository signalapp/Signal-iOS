//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BackupKeepKeySafeSheet: HeroSheetViewController {
    static var seeKeyAgainButtonTitle: String {
        return OWSLocalizedString(
            "BACKUP_ONBOARDING_CONFIRM_KEY_SEE_KEY_AGAIN_BUTTON_TITLE",
            comment: "Title for a button offering to let users see their 'Recovery Key'.",
        )
    }

    /// - Parameter onContinue
    /// Called after dismissing this sheet when the user taps "Continue",
    /// indicating acknowledgement of the "keep key safe" warning.
    /// - Parameter onSeeKeyAgain
    /// Called after dismissing this sheet when the user taps "See Key Again",
    /// indicating they want another opportunity to record their key.
    init(
        onContinue: @escaping () -> Void,
        onSeeKeyAgain: @escaping () -> Void,
    ) {
        super.init(
            hero: .image(.backupsKey),
            title: OWSLocalizedString(
                "BACKUP_ONBOARDING_CONFIRM_KEY_KEEP_KEY_SAFE_SHEET_TITLE",
                comment: "Title for a sheet warning users to their 'Recovery Key' safe.",
            ),
            body: OWSLocalizedString(
                "BACKUP_ONBOARDING_CONFIRM_KEY_KEEP_KEY_SAFE_SHEET_BODY",
                comment: "Body for a sheet warning users to their 'Recovery Key' safe.",
            ),
            primaryButton: Button(
                title: CommonStrings.continueButton,
                action: { sheet in
                    sheet.dismiss(animated: true) {
                        onContinue()
                    }
                },
            ),
            secondaryButton: Button(
                title: Self.seeKeyAgainButtonTitle,
                style: .secondary,
                action: .custom({ sheet in
                    sheet.dismiss(animated: true) {
                        onSeeKeyAgain()
                    }
                }),
            ),
        )
    }
}
