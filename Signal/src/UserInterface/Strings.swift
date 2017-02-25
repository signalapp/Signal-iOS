//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * Strings re-used in multiple places should be added here.
 */
@objc class CallStrings: NSObject {
    static let callBackButtonTitle = NSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action")
    static let missedCallNotificationBody = NSLocalizedString("MISSED_CALL", comment: "notification title")
    static let missedCallNotificationBodyWithCallerName = NSLocalizedString("MSGVIEW_MISSED_CALL", comment: "notification title. Embeds {{Caller's Name}}")
    static let callStatusFormat = NSLocalizedString("CALL_STATUS_FORMAT", comment: "embeds {{Call Status}} in call screen label. For ongoing calls, {{Call Status}} is a seconds timer like 01:23, otherwise {{Call Status}} is a short text like 'Ringing', 'Busy', or 'Failed Call'")
}
