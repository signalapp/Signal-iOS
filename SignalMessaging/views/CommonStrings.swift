//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Strings re-used in multiple places should be added here.
 */

@objc public class CommonStrings: NSObject {
    @objc
    static public let dismissButton = NSLocalizedString("DISMISS_BUTTON_TEXT", comment: "Short text to dismiss current modal / actionsheet / screen")
    @objc
    static public let cancelButton = NSLocalizedString("TXT_CANCEL_TITLE", comment: "Label for the cancel button in an alert or action sheet.")
    @objc
    static public let retryButton = NSLocalizedString("RETRY_BUTTON_TEXT", comment: "Generic text for button that retries whatever the last action was.")
    @objc
    static public let openSettingsButton = NSLocalizedString("OPEN_SETTINGS_BUTTON", comment: "Button text which opens the settings app")
    @objc
    static public let errorAlertTitle = NSLocalizedString("ALERT_ERROR_TITLE", comment: "")
}

@objc public class MessageStrings: NSObject {
    @objc
    static public let newGroupDefaultTitle = NSLocalizedString("NEW_GROUP_DEFAULT_TITLE", comment: "Used in place of the group name when a group has not yet been named.")
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

    // MARK: Missed Call Notification
    @objc
    static public let missedCallNotificationBodyWithoutCallerName = NSLocalizedString("MISSED_CALL", comment: "notification title")
    @objc
    static public let missedCallNotificationBodyWithCallerName = NSLocalizedString("MSGVIEW_MISSED_CALL_WITH_NAME", comment: "notification title. Embeds {{caller's name or phone number}}")

    // MARK: Missed with changed identity notification (for not previously verified identity)
    @objc
    static public let missedCallWithIdentityChangeNotificationBodyWithoutCallerName =  NSLocalizedString("MISSED_CALL_WITH_CHANGED_IDENTITY_BODY_WITHOUT_CALLER_NAME", comment: "notification title")
    @objc
    static public let missedCallWithIdentityChangeNotificationBodyWithCallerName =  NSLocalizedString("MISSED_CALL_WITH_CHANGED_IDENTITY_BODY_WITH_CALLER_NAME", comment: "notification title. Embeds {{caller's name or phone number}}")
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
