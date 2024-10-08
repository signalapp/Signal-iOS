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

    static var createCallLinkTitle: String {
        return OWSLocalizedString(
            "CALL_LINK_CREATE",
            comment: "Navigation bar title for the sheet used to create & configure a Call Link."
        )
    }

    static var addCallName: String {
        return OWSLocalizedString(
            "CALL_LINK_ADD_NAME",
            comment: "Button to open a screen to edit the name of a Call Link. Also used as the title of that screen once it opens."
        )
    }

    static var editCallName: String {
        return OWSLocalizedString(
            "CALL_LINK_EDIT_NAME",
            comment: "Button to open a screen to edit the name of a Call Link. Also used as the title of that screen once it opens."
        )
    }

    static var approveAllMembers: String {
        return OWSLocalizedString(
            "CALL_LINK_REQUIRE_APPROVAL",
            comment: "Name of a toggle switch to enable/disable admin approval for joining a Call Link."
        )
    }

    static var shareLinkViaSignal: String {
        return OWSLocalizedString(
            "CALL_LINK_SHARE_VIA_SIGNAL",
            comment: "Button to open UI to share a Call Link with someone on Signal."
        )
    }

    static var shareLinkViaSystem: String {
        return OWSLocalizedString(
            "CALL_LINK_SHARE_VIA_SYSTEM",
            comment: "Button to open the system share sheet to share a Call Link."
        )
    }

    static var copyLinkToClipboard: String {
        return OWSLocalizedString(
            "CALL_LINK_COPY",
            comment: "Button to copy a Call Link to the clipboard."
        )
    }

    static var joinCallPillButtonTitle: String {
        return OWSLocalizedString(
            "JOIN_CALL_PILL_BUTTON",
            comment: "Button to join an active group call"
        )
    }

    static var callLinkErrorSheetTitle: String {
        OWSLocalizedString(
            "CALL_LINK_CREATION_OR_UPDATE_FAILURE_SHEET_TITLE",
            comment: "Title of sheet presented when call link creation or update fails."
        )
    }

    static var callLinkUpdateErrorSheetDescription: String {
        OWSLocalizedString(
            "CALL_LINK_UPDATE_FAILURE_SHEET_DESCRIPTION",
            comment: "Description of sheet presented when call link update fails."
        )
    }

    static func callLinkMoreRequests(count: Int) -> String {
        String(
            format: OWSLocalizedString(
                "CALL_LINK_JOIN_REQUEST_AMOUNT_MORE_BUTTON_%ld",
                tableName: "PluralAware",
                comment: "Label for button below a request to join a call link indicating how many more requests there are. Tapping it opens a list of requests. Embeds {{ count }}"
            ),
            count
        )
    }

    static var callLink: String {
        return OWSLocalizedString(
            "CALL_LINK",
            comment: "Label or title used to represent a call that used a call link."
        )
    }

    static var callDetails: String {
        return OWSLocalizedString(
            "CALL_DETAILS",
            comment: "Title used to represent details about a call."
        )
    }
}
