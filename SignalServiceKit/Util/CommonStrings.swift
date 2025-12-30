//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/**
 * Strings re-used in multiple places should be added here.
 */
public enum CommonStrings {

    public static var archiveAction: String {
        OWSLocalizedString("ARCHIVE_ACTION", comment: "Label for the archive button for conversations list view")
    }

    public static var acknowledgeButton: String {
        OWSLocalizedString(
            "ALERT_ACTION_ACKNOWLEDGE",
            comment:
            "generic button text to acknowledge that the corresponding text was read.",
        )
    }

    public static var backButton: String {
        OWSLocalizedString("BACK_BUTTON", comment: "return to the previous screen")
    }

    public static var cancelButton: String {
        OWSLocalizedString("TXT_CANCEL_TITLE", comment: "Label for the cancel button in an alert or action sheet.")
    }

    public static var continueButton: String {
        OWSLocalizedString("BUTTON_CONTINUE", comment: "Label for 'continue' button.")
    }

    public static var discardButton: String {
        OWSLocalizedString("ALERT_DISCARD_BUTTON", comment: "The label for the 'discard' button in alerts and action sheets.")
    }

    public static var dismissButton: String {
        OWSLocalizedString("DISMISS_BUTTON_TEXT", comment: "Short text to dismiss current modal / actionsheet / screen")
    }

    public static var selectButton: String {
        OWSLocalizedString("BUTTON_SELECT", comment: "Button text to enable batch selection mode")
    }

    public static var doneButton: String {
        OWSLocalizedString("BUTTON_DONE", comment: "Label for generic done button.")
    }

    public static var nextButton: String {
        OWSLocalizedString("BUTTON_NEXT", comment: "Label for the 'next' button.")
    }

    public static var previousButton: String {
        OWSLocalizedString("BUTTON_PREVIOUS", comment: "Label for the 'previous' button.")
    }

    public static var skipButton: String {
        OWSLocalizedString("NAVIGATION_ITEM_SKIP_BUTTON", comment: "A button to skip a view.")
    }

    public static var deleteButton: String {
        OWSLocalizedString(
            "TXT_DELETE_TITLE",
            comment: "Label for the delete button in an alert or action sheet.",
        )
    }

    public static var deleteForMeButton: String {
        OWSLocalizedString(
            "MESSAGE_ACTION_DELETE_FOR_YOU",
            comment: "The title for the action that deletes a message for the local user only.",
        )
    }

    public static var retryButton: String {
        OWSLocalizedString(
            "RETRY_BUTTON_TEXT",
            comment: "Generic text for button that retries whatever the last action was.",
        )
    }

    public static var okayButton: String {
        OWSLocalizedString("BUTTON_OKAY", comment: "Label for the 'okay' button.")
    }

    public static var okButton: String {
        OWSLocalizedString("OK", comment: "Label for the 'ok' button.")
    }

    public static var copyButton: String {
        OWSLocalizedString("BUTTON_COPY", comment: "Label for the 'copy' button.")
    }

    public static var setButton: String {
        OWSLocalizedString("BUTTON_SET", comment: "Label for the 'set' button.")
    }

    public static var editButton: String {
        OWSLocalizedString("BUTTON_EDIT", comment: "Label for the 'edit' button.")
    }

    public static var saveButton: String {
        OWSLocalizedString(
            "ALERT_SAVE",
            comment: "The label for the 'save' button in action sheets.",
        )
    }

    public static var shareButton: String {
        OWSLocalizedString("BUTTON_SHARE", comment: "Label for the 'share' button.")
    }

    public static var goToSettingsButton: String {
        OWSLocalizedString(
            "GO_TO_SETTINGS_BUTTON",
            comment: "Label for the 'go to settings' button",
        )
    }

    public static var help: String {
        OWSLocalizedString("SETTINGS_HELP", comment: "Title for help button and help pages in app settings.")
    }

    public static var openAppSettingsButton: String {
        OWSLocalizedString(
            "OPEN_APP_SETTINGS_BUTTON",
            comment: "Title for button which opens the in-app settings",
        )
    }

    public static var openSystemSettingsButton: String {
        OWSLocalizedString(
            "OPEN_SETTINGS_BUTTON",
            comment: "Button text which opens the settings app",
        )
    }

    public static var errorAlertTitle: String {
        OWSLocalizedString("ALERT_ERROR_TITLE", comment: "")
    }

    public static var searchPlaceholder: String {
        OWSLocalizedString(
            "SEARCH_FIELD_PLACE_HOLDER_TEXT",
            comment: "placeholder text in an empty search field",
        )
    }

    public static var mainPhoneNumberLabel: String {
        OWSLocalizedString("PHONE_NUMBER_TYPE_MAIN", comment: "Label for 'Main' phone numbers.")
    }

    public static var contactSupport: String {
        OWSLocalizedString(
            "CONTACT_SUPPORT",
            comment: "Button text to initiate an email to signal support staff",
        )
    }

    public static var learnMore: String {
        OWSLocalizedString("LEARN_MORE", comment: "Label for the 'learn more' button.")
    }

    public static var copiedToClipboardToast: String {
        OWSLocalizedString("COPIED_TO_CLIPBOARD", comment: "Indicator that a value has been copied to the clipboard.")
    }

    public static var unarchiveAction: String {
        OWSLocalizedString(
            "UNARCHIVE_ACTION",
            comment: "Label for the unarchive button for conversations list view",
        )
    }

    public static var readAction: String {
        OWSLocalizedString("READ_ACTION", comment: "Pressing this button marks a thread as read")
    }

    public static var unreadAction: String {
        OWSLocalizedString("UNREAD_ACTION", comment: "Pressing this button marks a thread as unread")
    }

    public static var pinAction: String {
        OWSLocalizedString("PIN_ACTION", comment: "Pressing this button pins a thread")
    }

    public static var unpinAction: String {
        OWSLocalizedString("UNPIN_ACTION", comment: "Pressing this button un-pins a thread")
    }

    public static var switchOn: String {
        OWSLocalizedString("SWITCH_ON", comment: "Label for 'on' state of a switch control.")
    }

    public static var switchOff: String {
        OWSLocalizedString("SWITCH_OFF", comment: "Label for 'off' state of a switch control.")
    }

    public static var sendMessage: String {
        OWSLocalizedString(
            "ACTION_SEND_MESSAGE",
            comment: "Label for button that lets you send a message to a contact.",
        )
    }

    public static var yesButton: String {
        OWSLocalizedString("BUTTON_YES", comment: "Label for the 'yes' button.")
    }

    public static var noButton: String {
        OWSLocalizedString("BUTTON_NO", comment: "Label for the 'no' button.")
    }

    public static var redeemGiftButton: String {
        return OWSLocalizedString(
            "DONATION_ON_BEHALF_OF_A_FRIEND_REDEEM_BADGE",
            comment: "Label for a button used to redeem a badge that was received as a donation on your behalf.",
        )
    }

    public static var notNowButton: String {
        OWSLocalizedString("BUTTON_NOT_NOW", comment: "Label for the 'not now' button.")
    }

    public static var addButton: String {
        OWSLocalizedString("BUTTON_ADD", comment: "Label for the 'add' button.")
    }

    public static var viewButton: String {
        OWSLocalizedString("BUTTON_VIEW", comment: "Label for the 'view' button.")
    }

    public static var seeAllButton: String {
        OWSLocalizedString("SEE_ALL_BUTTON", comment: "Label for the 'see all' button.")
    }

    public static var muteButton: String {
        OWSLocalizedString("BUTTON_MUTE", comment: "Label for the 'mute' button.")
    }

    public static var unmuteButton: String {
        OWSLocalizedString("BUTTON_UNMUTE", comment: "Label for the 'unmute' button.")
    }

    public static var genericError: String {
        OWSLocalizedString("ALERT_ERROR_TITLE", comment: "Generic error indicator.")
    }

    public static var attachmentTypePhoto: String {
        OWSLocalizedString(
            "ATTACHMENT_TYPE_PHOTO",
            comment: "Short text label for a photo attachment, used for thread preview and on the lock screen",
        )
    }

    public static var attachmentTypeVideo: String {
        OWSLocalizedString(
            "ATTACHMENT_TYPE_VIDEO",
            comment: "Short text label for a video attachment, used for thread preview and on the lock screen",
        )
    }

    public static var attachmentTypeAnimated: String {
        OWSLocalizedString(
            "ATTACHMENT_TYPE_ANIMATED",
            comment: "Short text label for an animated attachment, used for thread preview and on the lock screen",
        )
    }

    public static var searchBarPlaceholder: String {
        OWSLocalizedString("INVITE_FRIENDS_PICKER_SEARCHBAR_PLACEHOLDER", comment: "Search")
    }

    public static var unknownUser: String {
        OWSLocalizedString("UNKNOWN_USER", comment: "Label indicating an unknown user.")
    }

    public static var you: String {
        OWSLocalizedString("YOU", comment: "Second person pronoun to represent the local user.")
    }

    public static var somethingWentWrongError: String {
        OWSLocalizedString(
            "SOMETHING_WENT_WRONG_ERROR",
            comment: "An error message generically indicating that something went wrong.",
        )
    }

    public static var somethingWentWrongTryAgainLaterError: String {
        OWSLocalizedString(
            "SOMETHING_WENT_WRONG_TRY_AGAIN_LATER_ERROR",
            comment: "An error message generically indicating that something went wrong, and that the user should try again later.",
        )
    }

    public static var scanQRCodeTitle: String {
        OWSLocalizedString(
            "SCAN_QR_CODE_VIEW_TITLE",
            comment: "Title for the 'scan QR code' view.",
        )
    }

    public static var betaLabel: String {
        OWSLocalizedString("BETA_LABEL", comment: "Beta label")
    }

    public static var dontShowAgainButton: String {
        OWSLocalizedString(
            "DONT_SHOW_AGAIN_BUTTON_TITLE",
            comment: "Label for a button that says 'Don't show again'.",
        )
    }
}

// MARK: -

public extension Usernames.RemoteMutationError {
    var localizedDescription: String {
        switch self {
        case .networkError:
            return OWSLocalizedString(
                "USERNAMES_REMOTE_MUTATION_ERROR_DESCRIPTION",
                comment: "An error message indicating that a usernames-related requeset failed because of a network error.",
            )
        case .otherError:
            return CommonStrings.somethingWentWrongTryAgainLaterError
        }
    }
}

// MARK: -

public enum MessageStrings {

    public static var conversationIsBlocked: String {
        OWSLocalizedString(
            "CONTACT_CELL_IS_BLOCKED",
            comment: "An indicator that a contact or group has been blocked.",
        )
    }

    public static var newGroupDefaultTitle: String {
        OWSLocalizedString(
            "NEW_GROUP_DEFAULT_TITLE",
            comment: "Used in place of the group name when a group has not yet been named.",
        )
    }

    public static var replyNotificationAction: String {
        OWSLocalizedString("PUSH_MANAGER_REPLY", comment: "Notification action button title")
    }

    public static var markAsReadNotificationAction: String {
        OWSLocalizedString("PUSH_MANAGER_MARKREAD", comment: "Notification action button title")
    }

    public static var reactWithThumbsUpNotificationAction: String {
        OWSLocalizedString(
            "PUSH_MANAGER_REACT_WITH_THUMBS_UP",
            comment: "Notification action button title for 'react with thumbs up.'",
        )
    }

    public static var sendButton: String {
        OWSLocalizedString("SEND_BUTTON_TITLE", comment: "Label for the button to send a message")
    }

    public static var noteToSelf: String {
        OWSLocalizedString("NOTE_TO_SELF", comment: "Label for 1:1 conversation with yourself.")
    }

    public static var viewOnceViewPhoto: String {
        OWSLocalizedString(
            "PER_MESSAGE_EXPIRATION_VIEW_PHOTO",
            comment: "Label for view-once messages indicating that user can tap to view the message's contents.",
        )
    }

    public static var viewOnceViewVideo: String {
        OWSLocalizedString(
            "PER_MESSAGE_EXPIRATION_VIEW_VIDEO",
            comment: "Label for view-once messages indicating that user can tap to view the message's contents.",
        )
    }

    public static var removePreviewButtonLabel: String {
        OWSLocalizedString(
            "REMOVE_PREVIEW",
            comment: "Accessibility label for a button that removes the preview from a drafted message.",
        )
    }
}

// MARK: -

public enum NotificationStrings {

    public static var missedCallBecauseOfIdentityChangeBody: String {
        OWSLocalizedString(
            "CALL_MISSED_BECAUSE_OF_IDENTITY_CHANGE_NOTIFICATION_BODY",
            comment: "notification body",
        )
    }

    public static var genericIncomingMessageNotification: String {
        OWSLocalizedString("GENERIC_INCOMING_MESSAGE_NOTIFICATION", comment: "notification title indicating the user generically has a new message")
    }

    /// Body for notification in a thread with a pending message request.
    public static var incomingMessageRequestNotification: String {
        OWSLocalizedString(
            "NOTIFICATION_BODY_INCOMING_MESSAGE_REQUEST",
            comment: "Body for a notification representing a message request.",
        )
    }

    /// This is the fallback message used for push notifications
    /// when the NSE or main app is unable to process them. We
    /// don't use it directly in the app, but need to maintain
    /// a reference to it for string generation.
    public static var indeterminateIncomingMessageNotification: String {
        OWSLocalizedString("APN_Message", comment: "notification body")
    }

    public static var incomingGroupMessageTitleFormat: String {
        OWSLocalizedString(
            "NEW_GROUP_MESSAGE_NOTIFICATION_TITLE",
            comment: "notification title. Embeds {{author name}} and {{group name}}",
        )
    }

    public static var incomingGroupStoryReplyTitleFormat: String {
        OWSLocalizedString(
            "NEW_GROUP_STORY_REPLY_NOTIFICATION_TITLE",
            comment: "notification title. Embeds {{ %1%@ author name, %2%@ group name}}",
        )
    }

    public static var failedToSendBody: String {
        OWSLocalizedString("SEND_FAILED_NOTIFICATION_BODY", comment: "notification body")
    }

    public static var groupCallSafetyNumberChangeBody: String {
        OWSLocalizedString(
            "GROUP_CALL_SAFETY_NUMBER_CHANGE_BODY",
            comment: "notification body when a group call participant joins with an untrusted safety number",
        )
    }

    public static var groupCallSafetyNumberChangeAtJoinBody: String {
        OWSLocalizedString(
            "GROUP_CALL_SAFETY_NUMBER_CHANGE_AT_JOIN_BODY",
            comment: "notification body when you join a group call and an already-joined participant has an untrusted safety number",
        )
    }

    public static var incomingReactionFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionTextMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_TEXT_MESSAGE_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}} and {{body text}}",
        )
    }

    public static var incomingReactionViewOnceMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_VIEW_ONCE_MESSAGE_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionStickerMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_STICKER_MESSAGE_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionContactShareMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_CONTACT_SHARE_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionAlbumMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_ALBUM_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionPhotoMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_PHOTO_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionVideoMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_VIDEO_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionVoiceMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_VOICE_MESSAGE_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionAudioMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_AUDIO_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionGifMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_GIF_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }

    public static var incomingReactionFileMessageFormat: String {
        OWSLocalizedString(
            "REACTION_INCOMING_NOTIFICATION_TO_FILE_BODY_FORMAT",
            comment: "notification body. Embeds {{reaction emoji}}",
        )
    }
}

// MARK: -

public enum CallStrings {
    static var callBackButtonTitle: String {
        return OWSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action")
    }

    static var showThreadButtonTitle: String {
        return OWSLocalizedString("SHOW_THREAD_BUTTON_TITLE", comment: "notification action")
    }

    public static var signalCall: String {
        return OWSLocalizedString(
            "SIGNAL_CALL",
            comment: "Shown in the header when the user hasn't provided a custom name for a call.",
        )
    }

    public static var callLinkDescription: String {
        return OWSLocalizedString(
            "CALL_LINK_LINK_PREVIEW_DESCRIPTION",
            comment: "Shown in a message bubble when you send a call link in a Signal chat",
        )
    }
}

// MARK: -

public enum MediaStrings {

    public static var allMedia: String {
        OWSLocalizedString("MEDIA_DETAIL_VIEW_ALL_MEDIA_BUTTON", comment: "nav bar button item")
    }
}

// MARK: -

public enum SafetyNumberStrings {

    public static var confirmSendButton: String {
        OWSLocalizedString(
            "SAFETY_NUMBER_CHANGED_CONFIRM_SEND_ACTION",
            comment: "button title to confirm sending to a recipient whose safety number recently changed",
        )
    }

    public static var verified: String {
        OWSLocalizedString(
            "PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
            comment: "Badge indicating that the user is verified.",
        )
    }
}

// MARK: -

public enum MegaphoneStrings {

    public static var remindMeLater: String {
        OWSLocalizedString("MEGAPHONE_REMIND_LATER", comment: "button title to snooze a megaphone")
    }

    public static var weWillRemindYouLater: String {
        OWSLocalizedString(
            "MEGAPHONE_WILL_REMIND_LATER",
            comment: "toast indicating that we will remind the user later",
        )
    }
}

// MARK: -

public enum StoryStrings {

    public static var repliesAndReactionsHeader: String {
        OWSLocalizedString(
            "STORIES_REPLIES_AND_REACTIONS_HEADER",
            comment: "Section header for the 'replies & reactions' section in stories settings",
        )
    }

    public static var repliesAndReactionsFooter: String {
        OWSLocalizedString(
            "STORIES_REPLIES_AND_REACTIONS_FOOTER",
            comment: "Section footer for the 'replies & reactions' section in stories settings",
        )
    }

    public static var repliesAndReactionsToggle: String {
        OWSLocalizedString(
            "STORIES_REPLIES_AND_REACTIONS_TOGGLE",
            comment: "Toggle text for the 'replies & reactions' switch in stories settings",
        )
    }
}
