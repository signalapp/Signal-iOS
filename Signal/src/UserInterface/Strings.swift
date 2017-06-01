//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Strings re-used in multiple places should be added here.
 */
@objc class CallStrings: NSObject {

    static let callStatusFormat = NSLocalizedString("CALL_STATUS_FORMAT", comment: "embeds {{Call Status}} in call screen label. For ongoing calls, {{Call Status}} is a seconds timer like 01:23, otherwise {{Call Status}} is a short text like 'Ringing', 'Busy', or 'Failed Call'")

    static let confirmAndCallButtonTitle = NSLocalizedString("SAFETY_NUMBER_CHANGED_CONFIRM_CALL_ACTION", comment: "alert button text to confirm placing an outgoing call after the recipients Safety Number has changed.")

    // MARK: Notification actions
    static let callBackButtonTitle = NSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action")
    static let confirmIdentityAndCallBackButtonTitle = NSLocalizedString("CONFIRM_IDENTITY_AND_CALLBACK_BUTTON_TITLE", comment: "notification action, confirming that it's OK to proceed calling after a caller's Safety Number has changed")
    static let showThreadButtonTitle = NSLocalizedString("SHOW_THREAD_BUTTON_TITLE", comment: "notification action")

    // MARK: Missed Call Notification
    static let missedCallNotificationBody = NSLocalizedString("MISSED_CALL", comment: "notification title")
    static let missedCallNotificationBodyWithCallerName = NSLocalizedString("MSGVIEW_MISSED_CALL_WITH_NAME", comment: "notification title. Embeds {{Caller's Name}}")
    static let missedCallNotificationBodyWithoutCallerName = NSLocalizedString("MSGVIEW_MISSED_CALL_WITHOUT_NAME", comment: "notification title.")

    // MARK: Missed with Unseen identity Notification
    static let rejectedCallWithUnseenIdentityChangeNotificationBody =  NSLocalizedString("MISSED_CALL_WITH_UNSEEN_IDENTITY_BODY", comment: "notification action")
    static let rejectedCallWithUnseenIdentityChangeNotificationBodyWithoutCallerName =  NSLocalizedString("MISSED_CALL_WITH_UNSEEN_IDENTITY_BODY_WITHOUT_CALLER_NAME", comment: "notification action")
    static let rejectedCallWithUnseenIdentityChangeNotificationBodyWithCallerName =  NSLocalizedString("MISSED_CALL_WITH_UNSEEN_IDENTITY_BODY_WITH_CALLER_NAME", comment: "notification action")
}
