//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

// MARK: - Strings

extension String {
    var e164FormattedAsPhoneNumberWithoutBreaks: String {
        let formatted = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: self)
        return formatted.replacingOccurrences(of: " ", with: "\u{00a0}")
    }
}

// MARK: - Layout margins

extension UIEdgeInsets {
    static func layoutMarginsForRegistration(
        _ horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> UIEdgeInsets {
        switch horizontalSizeClass {
        case .unspecified, .compact:
            return UIEdgeInsets(margin: 32)
        case .regular:
            return UIEdgeInsets(margin: 112)
        @unknown default:
            return UIEdgeInsets(margin: 32)
        }
    }
}

// MARK: - Colors

extension UIColor {
    static var colorForRegistrationTitleLabel: UIColor { Theme.primaryTextColor }
    static var colorForRegistrationExplanationLabel: UIColor { Theme.secondaryTextAndIconColor }
}

// MARK: - Labels

extension UILabel {
    static func titleLabelForRegistration(text: String) -> UILabel {
        let result = UILabel()
        result.text = text
        result.textColor = .colorForRegistrationTitleLabel
        result.font = UIFont.ows_dynamicTypeTitle1Clamped.ows_semibold
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }

    static func explanationLabelForRegistration(text: String) -> UILabel {
        let result = UILabel()
        result.textColor = .colorForRegistrationExplanationLabel
        result.font = UIFont.ows_dynamicTypeSubheadlineClamped
        result.text = text
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        return result
    }
}

// MARK: - Buttons

extension OWSFlatButton {
    static func primaryButtonForRegistration(title: String, target: Any, selector: Selector) -> OWSFlatButton {
        let result = insetButton(
            title: title,
            font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold,
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: target,
            selector: selector
        )
        result.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 14)
        return result
    }
}

// MARK: - Action sheets

extension ActionSheetController {
    enum RegistrationVerificationConfirmationMode {
        case sms
        case voice
    }

    static func forRegistrationVerificationConfirmation(
        mode: RegistrationVerificationConfirmationMode,
        e164: String,
        didConfirm: @escaping () -> Void,
        didRequestEdit: @escaping () -> Void
    ) -> ActionSheetController {
        let result = ActionSheetController(
            title: {
                let format = OWSLocalizedString(
                    "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_ALERT_TITLE_FORMAT",
                    comment: "Title for confirmation alert during phone number registration. Embeds {{phone number}}."
                )
                return String(format: format, e164.e164FormattedAsPhoneNumberWithoutBreaks)
            }(),
            message: OWSLocalizedString(
                "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_ALERT_MESSAGE",
                comment: "Message for confirmation alert during phone number registration."
            )
        )

        let confirmButtonTitle = CommonStrings.yesButton
        result.addAction(.init(title: confirmButtonTitle) { _ in didConfirm() })

        let editButtonTitle = OWSLocalizedString(
            "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_EDIT_BUTTON",
            comment: "A button allowing user to cancel registration and edit a phone number"
        )
        result.addAction(.init(title: editButtonTitle) { _ in didRequestEdit() })

        return result
    }
}
