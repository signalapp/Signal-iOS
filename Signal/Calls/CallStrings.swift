//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension CallStrings {
    static var confirmAndCallButtonTitle: String {
        return OWSLocalizedString(
            "SAFETY_NUMBER_CHANGED_CONFIRM_CALL_ACTION",
            comment: "alert button text to confirm placing an outgoing call after the recipients Safety Number has changed."
        )
    }

    static var callBackAlertTitle: String {
        return OWSLocalizedString(
            "CALL_USER_ALERT_TITLE",
            comment: "Title for alert offering to call a user."
        )
    }

    static var callBackAlertMessageFormat: String {
        return OWSLocalizedString(
            "CALL_USER_ALERT_MESSAGE_FORMAT",
            comment: "Message format for alert offering to call a user. Embeds {{the user's display name or phone number}}."
        )
    }

    static var callBackAlertCallButton: String {
        return OWSLocalizedString(
            "CALL_USER_ALERT_CALL_BUTTON",
            comment: "Label for call button for alert offering to call a user."
        )
    }

    static var lowerHandButton: String {
        return OWSLocalizedString(
            "RAISED_HANDS_LOWER_HAND_BUTTON",
            comment: "Label for a button to lower your raised hand in a call."
        )
    }

    static var joinGroupCall: String {
        return OWSLocalizedString(
            "GROUP_CALL_JOIN_BUTTON",
            comment: "Button to join an ongoing group call"
        )
    }
}
