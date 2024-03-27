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

    /// Waits until `name`/`object` is posted.
    public func observeOnce(_ name: Notification.Name, object: Any? = nil) async {
        await withCheckedContinuation { continuation in
            // Concurrency in this method is nontrivial. There are at least two
            // relevant race conditions:
            //
            // (1) Multiple threads could post a notification at the same time, and
            // this will trigger multiple callbacks, even if you call `removeObserver`
            // as quickly as possible. We guard against this with an atomic
            // compare-and-swap to set the observer to nil.
            //
            // (2) When initially registering the observer, it's possible that another
            // thread could be posting the notifiation at the same time. If the
            // notification callback happens before we've assigned the initial value to
            // the atomic observer value, we'll drop that notification. We avoid that
            // problem by ensuring that the `addObserver` call and assignment of the
            // observer happen atomically.
            //
            // Memory management in this method is also non-trivial. The observer
            // captured in the block must be set to nil to avoid leaking memory.
            let observer = AtomicOptional<NSObjectProtocol>(nil, lock: AtomicLock())
            _ = observer.map { _ in
                return addObserver(forName: name, object: object, queue: nil, using: { [weak self] notification in
                    guard let observer = observer.swap(nil) else {
                        return
                    }
                    self?.removeObserver(observer)
                    continuation.resume(returning: ())
                })
            }
        }
    }

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
