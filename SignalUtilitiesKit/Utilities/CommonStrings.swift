//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
    static public let doneButton = NSLocalizedString("BUTTON_DONE", comment: "Label for generic done button.")
    @objc
    static public let retryButton = "RETRY_BUTTON_TEXT".localized()
    @objc
    static public let openSettingsButton = NSLocalizedString("OPEN_SETTINGS_BUTTON", comment: "Button text which opens the settings app")
    @objc
    static public let errorAlertTitle = NSLocalizedString("ALERT_ERROR_TITLE", comment: "")
}

@objc public class MessageStrings: NSObject {
    @objc
    static public let replyNotificationAction = NSLocalizedString("PUSH_MANAGER_REPLY", comment: "Notification action button title")

    @objc
    static public let markAsReadNotificationAction = NSLocalizedString("PUSH_MANAGER_MARKREAD", comment: "Notification action button title")

    @objc
    static public let sendButton = "SEND_BUTTON_TITLE".localized()
}

@objc
public class NotificationStrings: NSObject {
    @objc
    static public let incomingMessageBody = NSLocalizedString("APN_Message", comment: "notification body")
    
    @objc
    static public let incomingCollapsedMessagesBody = NSLocalizedString("APN_Collapsed_Messages", comment: "collapsed notification body for background polling")

    @objc
    static public let incomingGroupMessageTitleFormat = NSLocalizedString("NEW_GROUP_MESSAGE_NOTIFICATION_TITLE", comment: "notification title. Embeds {{author name}} and {{group name}}")

    @objc
    static public let failedToSendBody = "SEND_FAILED_NOTIFICATION_BODY".localized()
}

@objc public class CallStrings: NSObject {
    // MARK: Notification actions
    @objc
    static public let showThreadButtonTitle = "SHOW_THREAD_BUTTON_TITLE".localized()
}

@objc public class MediaStrings: NSObject {
    @objc
    static public let allMedia = NSLocalizedString("MEDIA_DETAIL_VIEW_ALL_MEDIA_BUTTON", comment: "nav bar button item")
    @objc
    static public let media = NSLocalizedString("MEDIA_TAB_TITLE", comment: "media tab title")
    @objc
    static public let document = NSLocalizedString("DOCUMENT_TAB_TITLE", comment: "document tab title")
}
