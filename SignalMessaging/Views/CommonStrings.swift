//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Strings re-used in multiple places should be added here.
 */

@objc public class CommonStrings: NSObject {
    @objc
    static public let backButton = NSLocalizedString("BACK_BUTTON", comment: "return to the previous screen")

    @objc
    static public let continueButton = NSLocalizedString("BUTTON_CONTINUE", comment: "Label for 'continue' button.")

    @objc
    static public let dismissButton = NSLocalizedString("DISMISS_BUTTON_TEXT", comment: "Short text to dismiss current modal / actionsheet / screen")

    @objc
    static public let cancelButton = NSLocalizedString("TXT_CANCEL_TITLE", comment: "Label for the cancel button in an alert or action sheet.")

    @objc
    static public let doneButton = NSLocalizedString("BUTTON_DONE", comment: "Label for generic done button.")

    @objc
    static public let nextButton = NSLocalizedString("BUTTON_NEXT", comment: "Label for the 'next' button.")

    @objc
    static public let retryButton = NSLocalizedString("RETRY_BUTTON_TEXT", comment: "Generic text for button that retries whatever the last action was.")

    @objc
    static public let openSettingsButton = NSLocalizedString("OPEN_SETTINGS_BUTTON", comment: "Button text which opens the settings app")

    @objc
    static public let errorAlertTitle = NSLocalizedString("ALERT_ERROR_TITLE", comment: "")

    @objc
    static public let searchPlaceholder = NSLocalizedString("SEARCH_FIELD_PLACE_HOLDER_TEXT", comment: "placeholder text in an empty search field")

    @objc
    static public let mainPhoneNumberLabel = NSLocalizedString("PHONE_NUMBER_TYPE_MAIN", comment: "Label for 'Main' phone numbers.")

    @objc
    static public let contactSupport = NSLocalizedString("CONTACT_SUPPORT", comment: "Button text to initiate an email to signal support staff")
}

@objc
public class CommonFormats: NSObject {
    @objc
    static public func formatUsername(_ username: String) -> String? {
        guard let username = username.filterForDisplay else { return nil }
        return NSLocalizedString("USERNAME_PREFIX",
                                 comment: "A prefix appeneded to all usernames when displayed") + username
    }
}

@objc
public class MessageStrings: NSObject {

    @objc
    static public let conversationIsBlocked = NSLocalizedString("CONTACT_CELL_IS_BLOCKED", comment: "An indicator that a contact or group has been blocked.")

    @objc
    static public let newGroupDefaultTitle = NSLocalizedString("NEW_GROUP_DEFAULT_TITLE", comment: "Used in place of the group name when a group has not yet been named.")

    @objc
    static public let replyNotificationAction = NSLocalizedString("PUSH_MANAGER_REPLY", comment: "Notification action button title")

    @objc
    static public let markAsReadNotificationAction = NSLocalizedString("PUSH_MANAGER_MARKREAD", comment: "Notification action button title")

    @objc
    static public let sendButton =  NSLocalizedString("SEND_BUTTON_TITLE", comment: "Label for the button to send a message")

    @objc
    static public let noteToSelf = NSLocalizedString("NOTE_TO_SELF", comment: "Label for 1:1 conversation with yourself.")

    @objc
    static public let viewOnceViewPhoto = NSLocalizedString("PER_MESSAGE_EXPIRATION_VIEW_PHOTO", comment: "Label for view-once messages indicating that user can tap to view the message's contents.")

    @objc
    static public let viewOnceViewVideo = NSLocalizedString("PER_MESSAGE_EXPIRATION_VIEW_VIDEO", comment: "Label for view-once messages indicating that user can tap to view the message's contents.")
}

@objc
public class NotificationStrings: NSObject {
    @objc
    static public let incomingCallBody = NSLocalizedString("CALL_INCOMING_NOTIFICATION_BODY", comment: "notification body")

    @objc
    static public let missedCallBody = NSLocalizedString("CALL_MISSED_NOTIFICATION_BODY", comment: "notification body")

    @objc
    static public let missedCallBecauseOfIdentityChangeBody = NSLocalizedString("CALL_MISSED_BECAUSE_OF_IDENTITY_CHANGE_NOTIFICATION_BODY", comment: "notification body")

    @objc
    static public let incomingMessageBody = NSLocalizedString("APN_Message", comment: "notification body")

    @objc
    static public let incomingGroupMessageTitleFormat = NSLocalizedString("NEW_GROUP_MESSAGE_NOTIFICATION_TITLE", comment: "notification title. Embeds {{author name}} and {{group name}}")

    @objc
    static public let failedToSendBody = NSLocalizedString("SEND_FAILED_NOTIFICATION_BODY", comment: "notification body")

    @objc
    static public let incomingReactionFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_BODY_FORMAT",
                                                                 comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionTextMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_TEXT_MESSAGE_BODY_FORMAT",
                                                                            comment: "notification body. Embeds {{reaction emoji}} and {{body text}}")

    @objc
    static public let incomingReactionViewOnceMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_VIEW_ONCE_MESSAGE_BODY_FORMAT",
                                                                                comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionStickerMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_STICKER_MESSAGE_BODY_FORMAT",
                                                                               comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionContactShareMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_CONTACT_SHARE_BODY_FORMAT",
                                                                                    comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionAlbumMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_ALBUM_BODY_FORMAT",
                                                                             comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionPhotoMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_PHOTO_BODY_FORMAT",
                                                                             comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionVideoMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_VIDEO_BODY_FORMAT",
                                                                             comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionVoiceMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_VOICE_MESSAGE_BODY_FORMAT",
                                                                             comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionAudioMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_AUDIO_BODY_FORMAT",
                                                                             comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionGifMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_GIF_BODY_FORMAT",
                                                                            comment: "notification body. Embeds {{reaction emoji}}")

    @objc
    static public let incomingReactionFileMessageFormat = NSLocalizedString("REACTION_INCOMING_NOTIFICATION_TO_FILE_BODY_FORMAT",
                                                                            comment: "notification body. Embeds {{reaction emoji}}")
}

@objc public class CallStrings: NSObject {
    @objc
    static public let callStatusFormat = NSLocalizedString("CALL_STATUS_FORMAT", comment: "embeds {{Call Status}} in call screen label. For ongoing calls, {{Call Status}} is a seconds timer like 01:23, otherwise {{Call Status}} is a short text like 'Ringing', 'Busy', or 'Failed Call'")

    @objc
    static public let confirmAndCallButtonTitle = NSLocalizedString("SAFETY_NUMBER_CHANGED_CONFIRM_CALL_ACTION", comment: "alert button text to confirm placing an outgoing call after the recipients Safety Number has changed.")

    @objc
    static public let callBackAlertTitle = NSLocalizedString("CALL_USER_ALERT_TITLE", comment: "Title for alert offering to call a user.")
    @objc
    static public let callBackAlertMessageFormat = NSLocalizedString("CALL_USER_ALERT_MESSAGE_FORMAT", comment: "Message format for alert offering to call a user. Embeds {{the user's display name or phone number}}.")
    @objc
    static public let callBackAlertCallButton = NSLocalizedString("CALL_USER_ALERT_CALL_BUTTON", comment: "Label for call button for alert offering to call a user.")

    // MARK: Notification actions
    @objc
    static public let callBackButtonTitle = NSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action")
    @objc
    static public let showThreadButtonTitle = NSLocalizedString("SHOW_THREAD_BUTTON_TITLE", comment: "notification action")
    @objc
    static public let answerCallButtonTitle = NSLocalizedString("ANSWER_CALL_BUTTON_TITLE", comment: "notification action")
    @objc
    static public let declineCallButtonTitle = NSLocalizedString("REJECT_CALL_BUTTON_TITLE", comment: "notification action")
}

@objc public class MediaStrings: NSObject {
    @objc
    static public let allMedia = NSLocalizedString("MEDIA_DETAIL_VIEW_ALL_MEDIA_BUTTON", comment: "nav bar button item")
}

@objc public class SafetyNumberStrings: NSObject {
    @objc
    static public let confirmSendButton = NSLocalizedString("SAFETY_NUMBER_CHANGED_CONFIRM_SEND_ACTION",
                                                      comment: "button title to confirm sending to a recipient whose safety number recently changed")
}

@objc public class MegaphoneStrings: NSObject {
    @objc
    static public let remindMeLater = NSLocalizedString("MEGAPHONE_REMIND_LATER", comment: "button title to snooze a megaphone")

    @objc
    static public let weWillRemindYouLater = NSLocalizedString("MEGAPHONE_WILL_REMIND_LATER", comment: "toast indicating that we will remind the user later")
}
