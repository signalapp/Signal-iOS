//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension CallsListViewController {
    enum Strings {
        static var selectCallsButtonTitle: String { OWSLocalizedString(
            "CALLS_TAB_SELECT_CALLS_BUTTON_TITLE",
            comment: "Title for a button allowing the user to select one or more calls, from the Calls Tab."
        ) }

        static var deleteAllCallsButtonTitle: String { OWSLocalizedString(
            "CALLS_TAB_DELETE_ALL_CALLS_BUTTON_TITLE",
            comment: "Title for a button allowing the user to delete all the calls from the Calls Tab."
        ) }

        static var deleteAllCallsPromptTitle: String { OWSLocalizedString(
            "CALLS_TAB_DELETE_ALL_CALLS_PROMPT_TITLE",
            comment: "Title for a prompt confirming that the user wants to delete all the calls from the Calls Tab."
        ) }

        static var deleteAllCallsPromptMessage: String { OWSLocalizedString(
            "CALLS_TAB_DELETE_ALL_CALLS_PROMPT_MESSAGE",
            comment: "Message for a prompt confirming that the user wants to delete all the calls from the Calls Tab."
        ) }

        static var filterPickerOptionAll: String { OWSLocalizedString(
            "CALLS_TAB_FILTER_PICKER_OPTION_ALL",
            comment: "An option in a segmented control in the Calls Tab allowing the user to select the filter option 'all calls'; i.e., 'unfiltered'."
        ) }

        static var filterPickerOptionMissed: String { OWSLocalizedString(
            "CALLS_TAB_FILTER_PICKER_OPTION_MISSED",
            comment: "An option in a segmented control in the Calls Tab allowing the user to select the filter option 'missed calls'."
        ) }

        static var callDirectionLabelOutgoing: String { OWSLocalizedString(
            "CALLS_TAB_CALL_DIRECTION_LABEL_OUTGOING",
            comment: "Label for an entry in the Calls Tab describing a call as outgoing."
        ) }

        static var callDirectionLabelIncoming: String { OWSLocalizedString(
            "CALLS_TAB_CALL_DIRECTION_LABEL_INCOMING",
            comment: "Label for an entry in the Calls Tab describing a call as incoming."
        ) }

        static var callDirectionLabelMissed: String { OWSLocalizedString(
            "CALLS_TAB_CALL_DIRECTION_LABEL_MISSED",
            comment: "Label for an entry in the Calls Tab describing a call as missed."
        ) }

        static var searchNoResultsFoundLabelFormat: String { OWSLocalizedString(
            "CALLS_TAB_SEARCH_NO_RESULTS_FOUND_LABEL_FORMAT",
            comment: "Label for a view explaining that no search results were found in the Calls Tab. Embeds {{ the search term }}."
        ) }

        static var noRecentCallsLabel: String { OWSLocalizedString(
            "CALLS_TAB_NO_RECENT_CALLS_LABEL",
            comment: "Label explaining that the user has no recent calls, so their Calls Tab is empty."
        ) }

        static var noRecentCallsSuggestionLabel: String { OWSLocalizedString(
            "CALLS_TAB_NO_RECENT_CALLS_SUGGESTION_LABEL",
            comment: "Label suggesting that the user start a call, shown when their Calls Tab is empty."
        ) }

        static var noMissedCallsLabel: String { OWSLocalizedString(
            "CALLS_TAB_NO_MISSED_CALLS_LABEL",
            comment: "Label explaining that the user has no missed calls, so their Calls Tab is empty."
        ) }

        static var goToChatActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_GO_TO_CHAT_ACTION_TITLE",
            comment: "Title for an action, either long-press context menu or swipe, offering to take the user to the chat associated with a call in the Calls Tab."
        ) }

        static var joinVoiceCallActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_JOIN_VOICE_CALL_ACTION_TITLE",
            comment: "Title for a long-press context menu action to join a voice call, triggered from a call in the Calls Tab."
        ) }

        static var joinVideoCallActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_JOIN_VIDEO_CALL_ACTION_TITLE",
            comment: "Title for a long-press context menu action to join a video call, triggered from a call in the Calls Tab."
        ) }

        static var returnToCallActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_RETURN_TO_CALL_ACTION_TITLE",
            comment: "Title for a long-press context menu action to return to a call the user is actively participating in, triggered from a call in the Calls Tab."
        ) }

        static var startVoiceCallActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_START_VOICE_CALL_ACTION_TITLE",
            comment: "Title for a long-press context menu action to start a voice call, triggered from a call in the Calls Tab."
        ) }

        static var startVideoCallActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_START_VIDEO_CALL_ACTION_TITLE",
            comment: "Title for a long-press context menu action to start a video call, triggered from a call in the Calls Tab."
        ) }

        static var viewCallInfoActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_VIEW_CALL_INFO_ACTION_TITLE",
            comment: "Title for a long-press context menu action to view info about a call, triggered from a call in the Calls Tab."
        ) }

        static var selectCallActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_SELECT_CALL_ACTION_TITLE",
            comment: "Title for a long-press context menu action to select a call, triggered from a call in the Calls Tab."
        ) }

        static var deleteCallActionTitle: String { OWSLocalizedString(
            "CALLS_TAB_DELETE_CALL_ACTION_TITLE",
            comment: "Title for a long-press context menu action to delete a call, triggered from a call in the Calls Tab."
        ) }

        static var deleteMultipleTitleFormat: String { OWSLocalizedString(
            "CALLS_TAB_DELETE_MULTIPLE_TITLE", tableName: "PluralAware",
            comment: "Title for a confirmation popup when deleting multiple calls from the calls tab."
        ) }

        static var deleteMultipleMessage: String { OWSLocalizedString(
            "CALL_LINK_MULTI_CONFIRM",
            comment: "Text shown in a confirmation popup when deleting multiple calls from the calls tab."
        ) }

        static var deleteMultipleSuccessFormat: String { OWSLocalizedString(
            "CALL_LINK_MULTI_SUCCESS", tableName: "PluralAware",
            comment: "Text shown in a confirmation popup when deleting multiple calls from the calls tab."
        ) }

        static var deleteMultipleError: String { OWSLocalizedString(
            "CALL_LINK_SOME_NOT_DELETED",
            comment: "An error alert that's shown when deleting multiple calls and some of them couldn't be deleted."
        ) }

        static var joinCallButtonTitle: String { OWSLocalizedString(
            "CALLS_TAB_JOIN_CALL_BUTTON_TITLE",
            comment: "Title for a button offering to let the user join an ongoing call, associated with a call in the Calls Tab."
        ) }

        static var returnToCallButtonTitle: String { OWSLocalizedString(
            "CALLS_TAB_RETURN_TO_CALL_BUTTON_TITLE",
            comment: "Title for a button offering to let the user return to an ongoing call they're already in, associated with a call in the Calls Tab."
        ) }

        static var coalescedCallsTitleFormat: String { OWSLocalizedString(
            "CALLS_TAB_COALESCED_CALLS_TITLE_FORMAT",
            comment: "Title for a row in the Calls Tab that represents multiple calls that have been coalesced together. Embeds {{ a title describing the coalesced calls }}, {{ the number of coalesced calls }}."
        ) }
    }
}
