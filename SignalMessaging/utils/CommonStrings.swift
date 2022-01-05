//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Strings re-used in multiple places should be added here.
 */
@objc
public class CommonStrings: NSObject {

    @objc
    static public var archiveAction: String {
        NSLocalizedString("ARCHIVE_ACTION", comment: "Label for the archive button for conversations list view")
    }

    @objc
    static public var backButton: String {
        NSLocalizedString("BACK_BUTTON", comment: "return to the previous screen")
    }

    @objc
    static public var continueButton: String {
        NSLocalizedString("BUTTON_CONTINUE", comment: "Label for 'continue' button.")
    }

    @objc
    static public var dismissButton: String {
        NSLocalizedString("DISMISS_BUTTON_TEXT",
                          comment: "Short text to dismiss current modal / actionsheet / screen")
    }

    @objc
    static public var cancelButton: String {
        NSLocalizedString("TXT_CANCEL_TITLE",
                          comment: "Label for the cancel button in an alert or action sheet.")
    }

    @objc
    static public var selectButton: String {
        NSLocalizedString("BUTTON_SELECT", comment: "Button text to enable batch selection mode")
    }

    @objc
    static public var doneButton: String {
        NSLocalizedString("BUTTON_DONE", comment: "Label for generic done button.")
    }

    @objc
    static public var nextButton: String {
        NSLocalizedString("BUTTON_NEXT", comment: "Label for the 'next' button.")
    }

    @objc
    static public var previousButton: String {
        NSLocalizedString("BUTTON_PREVIOUS", comment: "Label for the 'previous' button.")
    }

    @objc
    static public var skipButton: String {
        NSLocalizedString("NAVIGATION_ITEM_SKIP_BUTTON", comment: "A button to skip a view.")
    }

    @objc
    static public var deleteButton: String {
        NSLocalizedString("TXT_DELETE_TITLE",
                          comment: "Label for the delete button in an alert or action sheet.")
    }

    @objc
    static public var deleteForMeButton: String {
        NSLocalizedString(
            "MESSAGE_ACTION_DELETE_FOR_YOU",
            comment: "The title for the action that deletes a message for the local user only.")
    }

    @objc
    static public var retryButton: String {
        NSLocalizedString("RETRY_BUTTON_TEXT",
                          comment: "Generic text for button that retries whatever the last action was.")
    }

    @objc
    static public var okayButton: String {
        NSLocalizedString("BUTTON_OKAY", comment: "Label for the 'okay' button.")
    }

    @objc
    static public var okButton: String {
        NSLocalizedString("OK", comment: "Label for the 'ok' button.")
    }

    @objc
    static public var copyButton: String {
        NSLocalizedString("BUTTON_COPY", comment: "Label for the 'copy' button.")
    }

    @objc
    static public var setButton: String {
        NSLocalizedString("BUTTON_SET", comment: "Label for the 'set' button.")
    }

    @objc
    static public var editButton: String {
        NSLocalizedString("BUTTON_EDIT", comment: "Label for the 'edit' button.")
    }

    @objc
    static public var saveButton: String {
        NSLocalizedString("ALERT_SAVE",
                          comment: "The label for the 'save' button in action sheets.")
    }

    @objc
    static public var shareButton: String {
        NSLocalizedString("BUTTON_SHARE", comment: "Label for the 'share' button.")
    }

    @objc
    static public var help: String {
        NSLocalizedString("SETTINGS_HELP", comment: "Title for help button and help pages in app settings.")
    }

    @objc
    static public var openSettingsButton: String {
        NSLocalizedString("OPEN_SETTINGS_BUTTON", comment: "Button text which opens the settings app")
    }

    @objc
    static public var errorAlertTitle: String {
        NSLocalizedString("ALERT_ERROR_TITLE", comment: "")
    }

    @objc
    static public var searchPlaceholder: String {
        NSLocalizedString("SEARCH_FIELD_PLACE_HOLDER_TEXT",
                          comment: "placeholder text in an empty search field")
    }

    @objc
    static public var mainPhoneNumberLabel: String {
        NSLocalizedString("PHONE_NUMBER_TYPE_MAIN", comment: "Label for 'Main' phone numbers.")
    }

    @objc
    static public var contactSupport: String {
        NSLocalizedString("CONTACT_SUPPORT",
                          comment: "Button text to initiate an email to signal support staff")
    }

    @objc
    static public var learnMore: String {
        NSLocalizedString("LEARN_MORE", comment: "Label for the 'learn more' button.")
    }

    @objc
    static public var unarchiveAction: String {
        NSLocalizedString("UNARCHIVE_ACTION",
                          comment: "Label for the unarchive button for conversations list view")
    }

    @objc
    static public var readAction: String {
        NSLocalizedString("READ_ACTION", comment: "Pressing this button marks a thread as read")
    }

    @objc
    static public var unreadAction: String {
        NSLocalizedString("UNREAD_ACTION", comment: "Pressing this button marks a thread as unread")
    }

    @objc
    static public var pinAction: String {
        NSLocalizedString("PIN_ACTION", comment: "Pressing this button pins a thread")
    }

    @objc
    static public var unpinAction: String {
        NSLocalizedString("UNPIN_ACTION", comment: "Pressing this button upins a thread")
    }

    @objc
    static public var switchOn: String {
        NSLocalizedString("SWITCH_ON", comment: "Label for 'on' state of a switch control.")
    }

    @objc
    static public var switchOff: String {
        NSLocalizedString("SWITCH_OFF", comment: "Label for 'off' state of a switch control.")
    }

    @objc
    static public var sendMessage: String {
        NSLocalizedString("ACTION_SEND_MESSAGE",
                          comment: "Label for button that lets you send a message to a contact.")
    }

    @objc
    static public var yesButton: String {
        NSLocalizedString("BUTTON_YES", comment: "Label for the 'yes' button.")
    }

    @objc
    static public var noButton: String {
        NSLocalizedString("BUTTON_NO", comment: "Label for the 'no' button.")
    }

    @objc
    static public var notNowButton: String {
        NSLocalizedString("BUTTON_NOT_NOW", comment: "Label for the 'not now' button.")
    }

    @objc
    static public var addButton: String {
        NSLocalizedString("BUTTON_ADD", comment: "Label for the 'add' button.")
    }

    @objc
    static public var viewButton: String {
        NSLocalizedString("BUTTON_VIEW", comment: "Label for the 'view' button.")
    }

    @objc
    static public var startButton: String {
        NSLocalizedString("BUTTON_START", comment: "Label for the 'start' button.")
    }

    @objc
    static public var seeAllButton: String {
        NSLocalizedString("SEE_ALL_BUTTON", comment: "Label for the 'see all' button.")
    }

    @objc
    static public var muteButton: String {
        NSLocalizedString("BUTTON_MUTE", comment: "Label for the 'mute' button.")
    }

    @objc
    static public var unmuteButton: String {
        NSLocalizedString("BUTTON_UNMUTE", comment: "Label for the 'unmute' button.")
    }

    @objc
    static public var genericError: String {
        NSLocalizedString("ALERT_ERROR_TITLE", comment: "Generic error indicator.")
    }

    @objc
    static public var attachmentTypePhoto: String {
        NSLocalizedString("ATTACHMENT_TYPE_PHOTO",
                          comment: "Short text label for a photo attachment, used for thread preview and on the lock screen")
    }

    @objc
    static public var attachmentTypeVideo: String {
        NSLocalizedString("ATTACHMENT_TYPE_VIDEO",
                          comment: "Short text label for a video attachment, used for thread preview and on the lock screen")
    }

    @objc
    static public var searchBarPlaceholder: String {
        NSLocalizedString("INVITE_FRIENDS_PICKER_SEARCHBAR_PLACEHOLDER", comment: "Search")
    }
}

// MARK: -

@objc
public class CommonFormats: NSObject {
    @objc
    static public func formatUsername(_ username: String) -> String? {
        guard let username = username.filterForDisplay else { return nil }
        return (NSLocalizedString("USERNAME_PREFIX",
                                  comment: "A prefix appended to all usernames when displayed")
                + username)
    }
}

// MARK: -

@objc
public class MessageStrings: NSObject {

    @objc
    static public var conversationIsBlocked: String {
        NSLocalizedString("CONTACT_CELL_IS_BLOCKED",
                          comment: "An indicator that a contact or group has been blocked.")
    }

    @objc
    static public var newGroupDefaultTitle: String {
        NSLocalizedString("NEW_GROUP_DEFAULT_TITLE",
                          comment: "Used in place of the group name when a group has not yet been named.")
    }

    @objc
    static public var replyNotificationAction: String {
        NSLocalizedString("PUSH_MANAGER_REPLY", comment: "Notification action button title")
    }

    @objc
    static public var markAsReadNotificationAction: String {
        NSLocalizedString("PUSH_MANAGER_MARKREAD", comment: "Notification action button title")
    }

    @objc
    static public var reactWithThumbsUpNotificationAction: String {
        NSLocalizedString("PUSH_MANAGER_REACT_WITH_THUMBS_UP",
                          comment: "Notification action button title for 'react with thumbs up.'")
    }

    @objc
    static public var sendButton: String {
        NSLocalizedString("SEND_BUTTON_TITLE", comment: "Label for the button to send a message")
    }

    @objc
    static public var noteToSelf: String {
        NSLocalizedString("NOTE_TO_SELF", comment: "Label for 1:1 conversation with yourself.")
    }

    @objc
    static public var viewOnceViewPhoto: String {
        NSLocalizedString("PER_MESSAGE_EXPIRATION_VIEW_PHOTO",
                          comment: "Label for view-once messages indicating that user can tap to view the message's contents.")
    }

    @objc
    static public var viewOnceViewVideo: String {
        NSLocalizedString("PER_MESSAGE_EXPIRATION_VIEW_VIDEO",
                          comment: "Label for view-once messages indicating that user can tap to view the message's contents.")
    }

    @objc
    static public var removePreviewButtonLabel: String {
        NSLocalizedString("REMOVE_PREVIEW",
                          comment: "Accessibility label for a button that removes the preview from a drafted message.")
    }
}

// MARK: -

@objc
public class NotificationStrings: NSObject {
    @objc
    static public var incomingAudioCallBody: String {
        NSLocalizedString("CALL_AUDIO_INCOMING_NOTIFICATION_BODY", comment: "notification body")
    }

    @objc
    static public var incomingVideoCallBody: String {
        NSLocalizedString("CALL_VIDEO_INCOMING_NOTIFICATION_BODY", comment: "notification body")
    }

    @objc
    static public var missedAudioCallBody: String {
        NSLocalizedString("CALL_AUDIO_MISSED_NOTIFICATION_BODY", comment: "notification body")
    }

    @objc
    static public var missedVideoCallBody: String {
        NSLocalizedString("CALL_VIDEO_MISSED_NOTIFICATION_BODY", comment: "notification body")
    }

    @objc
    static public var missedCallBecauseOfIdentityChangeBody: String {
        NSLocalizedString("CALL_MISSED_BECAUSE_OF_IDENTITY_CHANGE_NOTIFICATION_BODY",
                          comment: "notification body")
    }

    @objc
    static public var genericIncomingMessageNotification: String {
        NSLocalizedString("GENERIC_INCOMING_MESSAGE_NOTIFICATION", comment: "notification title indicating the user generically has a new message")
    }

    /// This is the fallback message used for push notifications
    /// when the NSE or main app is unable to process them. We
    /// don't use it directly in the app, but need to maintain
    /// a reference to it for string generation.
    @objc
    static public var indeterminateIncomingMessageNotification: String {
        NSLocalizedString("APN_Message", comment: "notification body")
    }

    @objc
    static public var incomingGroupMessageTitleFormat: String {
        NSLocalizedString("NEW_GROUP_MESSAGE_NOTIFICATION_TITLE",
                          comment: "notification title. Embeds {{author name}} and {{group name}}")
    }

    @objc
    static public var failedToSendBody: String {
        NSLocalizedString("SEND_FAILED_NOTIFICATION_BODY", comment: "notification body")
    }

    @objc
    static public var groupCallSafetyNumberChangeBody: String {
        NSLocalizedString("GROUP_CALL_SAFETY_NUMBER_CHANGE_BODY",
                          comment: "notification body when a group call participant joins with an untrusted safety number")
    }

    @objc
    static public var incomingReactionFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionTextMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_TEXT_MESSAGE_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}} and {{body text}}")
    }

    @objc
    static public var incomingReactionViewOnceMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_VIEW_ONCE_MESSAGE_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionStickerMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_STICKER_MESSAGE_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionContactShareMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_CONTACT_SHARE_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionAlbumMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_ALBUM_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionPhotoMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_PHOTO_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionVideoMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_VIDEO_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionVoiceMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_VOICE_MESSAGE_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionAudioMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_AUDIO_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionGifMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_GIF_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }

    @objc
    static public var incomingReactionFileMessageFormat: String {
        NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_FILE_BODY_FORMAT",
                          comment: "notification body. Embeds {{reaction emoji}}")
    }
}

// MARK: -

@objc
public class CallStrings: NSObject {
    @objc
    static public var callStatusFormat: String {
        NSLocalizedString("CALL_STATUS_FORMAT",
                          comment: "embeds {{Call Status}} in call screen label. For ongoing calls, {{Call Status}} is a seconds timer like 01:23, otherwise {{Call Status}} is a short text like 'Ringing', 'Busy', or 'Failed Call'")
    }

    @objc
    static public var confirmAndCallButtonTitle: String {
        NSLocalizedString("SAFETY_NUMBER_CHANGED_CONFIRM_CALL_ACTION",
                          comment: "alert button text to confirm placing an outgoing call after the recipients Safety Number has changed.")
    }

    @objc
    static public var callBackAlertTitle: String {
        NSLocalizedString("CALL_USER_ALERT_TITLE",
                          comment: "Title for alert offering to call a user.")
    }
    @objc
    static public var callBackAlertMessageFormat: String {
        NSLocalizedString("CALL_USER_ALERT_MESSAGE_FORMAT",
                          comment: "Message format for alert offering to call a user. Embeds {{the user's display name or phone number}}.")
    }
    @objc
    static public var callBackAlertCallButton: String {
        NSLocalizedString("CALL_USER_ALERT_CALL_BUTTON",
                          comment: "Label for call button for alert offering to call a user.")
    }

    // MARK: - Notification actions

    @objc
    static public var callBackButtonTitle: String {
        NSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action")
    }
    @objc
    static public var showThreadButtonTitle: String {
        NSLocalizedString("SHOW_THREAD_BUTTON_TITLE", comment: "notification action")
    }
    @objc
    static public var answerCallButtonTitle: String {
        NSLocalizedString("ANSWER_CALL_BUTTON_TITLE", comment: "notification action")
    }
    @objc
    static public var declineCallButtonTitle: String {
        NSLocalizedString("REJECT_CALL_BUTTON_TITLE", comment: "notification action")
    }
}

// MARK: -

@objc
public class MediaStrings: NSObject {
    @objc
    static public var allMedia: String {
        NSLocalizedString("MEDIA_DETAIL_VIEW_ALL_MEDIA_BUTTON", comment: "nav bar button item")
    }
}

// MARK: -

@objc
public class SafetyNumberStrings: NSObject {
    @objc
    static public var confirmSendButton: String {
        NSLocalizedString("SAFETY_NUMBER_CHANGED_CONFIRM_SEND_ACTION",
                          comment: "button title to confirm sending to a recipient whose safety number recently changed")
    }
}

// MARK: -

@objc
public class MegaphoneStrings: NSObject {
    @objc
    static public var remindMeLater: String {
        NSLocalizedString("MEGAPHONE_REMIND_LATER", comment: "button title to snooze a megaphone")
    }

    @objc
    static public var weWillRemindYouLater: String {
        NSLocalizedString("MEGAPHONE_WILL_REMIND_LATER",
                          comment: "toast indicating that we will remind the user later")
    }
}
