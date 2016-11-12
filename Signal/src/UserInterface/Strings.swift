//  Created by Michael Kirk on 12/29/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation

@objc class Strings: NSObject {
    @objc class Calls: NSObject {
        static let callBackButtonTitle = NSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action")
        static let missedCallNotificationBody = NSLocalizedString("MISSED_CALL", comment: "notification title")
        static let missedCallNotificationBodyWithCallerName = NSLocalizedString("MSGVIEW_MISSED_CALL", comment: "notification title. Embeds {{Caller's Name}}")
    }
}
