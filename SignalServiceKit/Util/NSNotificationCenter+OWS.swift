//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// We often use notifications as way to publish events.
//
// We never need these events to be received synchronously,
// so we should always send them asynchronously to avoid any
// possible risk of deadlock.  These methods also ensure that
// the notifications are always fired on the main thread.
extension NotificationCenter {
    public func postOnMainThread(_ notification: Notification) {
        DispatchQueue.main.async {
            self.post(notification)
        }
    }

    public func postOnMainThread(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]? = nil) {
        DispatchQueue.main.async {
            self.post(name: name, object: object, userInfo: userInfo)
        }
    }
}

// MARK: -

extension NotificationCenter {
    public struct Observer {
        fileprivate let wrapped: AnyObject
    }

    public func addObserver(
        name: Notification.Name,
        block: @escaping (Notification) -> Void,
    ) -> Observer {
        return Observer(wrapped: addObserver(
            forName: name,
            object: nil,
            queue: nil,
            using: block,
        ))
    }

    public func removeObserver(_ observer: Observer) {
        removeObserver(observer.wrapped)
    }
}
