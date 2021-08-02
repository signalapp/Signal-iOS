//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// We often use notifications as way to publish events.
//
// We never need these events to be received synchronously,
// so we should always send them asynchronously to avoid any
// possible risk of deadlock.  These methods also ensure that
// the notifications are always fired on the main thread.
extension NotificationCenter {

    @objc
    public func postNotificationNameAsync(_ name: Notification.Name, object: Any?) {
        DispatchQueue.main.async {
            self.post(name: name, object: object)
        }
    }

    @objc
    public func postNotificationNameAsync(_ name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]? = nil) {
        DispatchQueue.main.async {
            self.post(name: name, object: object, userInfo: userInfo)
        }
    }
}
