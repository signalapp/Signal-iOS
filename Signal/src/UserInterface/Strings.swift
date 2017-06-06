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
    static let showThreadButtonTitle = NSLocalizedString("SHOW_THREAD_BUTTON_TITLE", comment: "notification action")

    // MARK: Missed Call Notification
    static let missedCallNotificationBodyWithoutCallerName = NSLocalizedString("MISSED_CALL", comment: "notification title")
    static let missedCallNotificationBodyWithCallerName = NSLocalizedString("MSGVIEW_MISSED_CALL_WITH_NAME", comment: "notification title. Embeds {{caller's name or phone number}}")

    // MARK: Missed with changed identity notification (for not previously verified identity)
    static let missedCallWithIdentityChangeNotificationBodyWithoutCallerName =  NSLocalizedString("MISSED_CALL_WITH_CHANGED_IDENTITY_BODY_WITHOUT_CALLER_NAME", comment: "notification title")
    static let missedCallWithIdentityChangeNotificationBodyWithCallerName =  NSLocalizedString("MISSED_CALL_WITH_CHANGED_IDENTITY_BODY_WITH_CALLER_NAME", comment: "notification title. Embeds {{caller's name or phone number}}")
}
