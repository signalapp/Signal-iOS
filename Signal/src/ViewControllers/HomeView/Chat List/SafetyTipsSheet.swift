//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

enum SafetyTipsSheet {
    static func makeSmsCodeRequestedSheet(timestampMs: UInt64, fromViewController: UIViewController) -> ActionSheetController {
        let timestampString = DateUtil.formatMessageTimestampForCVC(
            timestampMs,
            shouldUseLongFormat: true,
        )
        let bodyPartOne = OWSLocalizedString(
            "VERIFICATION_CODE_REQUESTED_HERO_BODY_FIRST",
            comment: "First part of body for a hero sheet informing the user a verification code was requested. {{ Embeds time the code was requested }}",
        )
        let bodyPartTwo = OWSLocalizedString(
            "VERIFICATION_CODE_REQUESTED_HERO_BODY_SECOND",
            comment: "Second part of body for a hero sheet informing the user a verification code was requested.",
        )
        let body: NSAttributedString = .composed(of: [
            bodyPartOne.styled(
                with: .font(.dynamicTypeHeadline),
                .color(UIColor.Signal.label),
                .paragraphSpacingAfter(4.0),
            ),
            "\n",
            timestampString.styled(
                with: .font(.dynamicTypeBody),
                .color(UIColor.Signal.label),
            ),
            "\n",
            bodyPartTwo.styled(
                with: .font(.dynamicTypeBody),
                .color(UIColor.Signal.label),
                .paragraphSpacingBefore(12.0),
            ),
        ])

        let actionSheet = ActionSheetController(
            message: body,
            image: UIImage(resource: .verificationcodeAlert96),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SAFETY_TIPS_BUTTON_ACTION_TITLE",
                comment: "Title for Safety Tips button in thread details.",
            ),
            handler: { [weak fromViewController] _ in
                let safetyTipsVC = SafetyTipsViewController(
                    mode: .smsRequest,
                    primaryButton: SafetyTipsViewController.Button(
                        title: OWSLocalizedString(
                            "SETTINGS_ACCOUNT_BUTTON",
                            comment: "Label for button in Safety Tips to go to 'account' page in settings.",
                        ),
                        action: {
                            SignalApp.shared.showAppSettings(mode: .accountSettings)
                        },
                    ),
                )
                fromViewController?.present(safetyTipsVC, animated: true)
            },
        ))
        actionSheet.addAction(.ok)
        return actionSheet
    }
}
