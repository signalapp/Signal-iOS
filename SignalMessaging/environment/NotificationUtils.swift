//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

@objc
public class NotificationUtils: NSObject {

    @objc
    public class func alertMessage(forErrorMessage message: TSErrorMessage, inThread thread: TSThread, notificationType: NotificationType) -> String? {
        if message.description.count < 1 {
            return nil
        }
        switch notificationType {
        case .namePreview,
         .nameNoPreview:
            return "\(thread.name): \(message.description)"
        case .noNameNoPreview:
            return message.description
        }
    }
}
