//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension NotificationCenter {
    func observe(once name: Notification.Name, object: Any? = nil) -> Guarantee<Notification> {
        let (guarantee, future) = Guarantee<Notification>.pending()
        let observer = addObserver(forName: name, object: object, queue: nil) { notification in
            future.resolve(notification)
        }
        guarantee.done { _ in self.removeObserver(observer) }
        return guarantee
    }
}
