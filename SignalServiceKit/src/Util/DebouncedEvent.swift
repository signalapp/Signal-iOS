//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// Invokes a "notification" block in response to
// "notification requests", but no more often than every N
// seconds.
@objc
public class DebouncedEvent: NSObject {
    private var hasEnqueuedNotification = false
    private var lastNotificationDate: Date?
    private let maxFrequencySeconds: TimeInterval
    private let notifyBlock: () -> Void
    private let notifyQueue: DispatchQueue
    private let unfairLock = UnfairLock()

    @objc
    public required init(maxFrequencySeconds: TimeInterval,
                         onQueue notifyQueue: DispatchQueue? = nil,
                         notifyBlock: @escaping () -> Void) {
        self.maxFrequencySeconds = maxFrequencySeconds
        self.notifyQueue = notifyQueue ?? DispatchQueue.global()
        self.notifyBlock = notifyBlock
    }

    @objc
    public func requestNotify() {
        unfairLock.withLock {
            if hasEnqueuedNotification {
                // Delayed notification is already enqueued.
                // We can ignore this request (de-bounce).
                return
            }
            if let lastNotificationDate = self.lastNotificationDate {
                let elapsed = abs(lastNotificationDate.timeIntervalSinceNow)
                let timerDelay = self.maxFrequencySeconds - elapsed
                if timerDelay > 0 {
                    // We've notified recently;
                    // wait before notifying again.
                    self.hasEnqueuedNotification = true
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + timerDelay) { [weak self] in
                        self?.fireDelayedNotification()
                    }
                    return
                }
            }

            // Notify immediately.
            self.lastNotificationDate = Date()
            notifyQueue.async {
                self.notifyBlock()
            }
        }
    }

    private func fireDelayedNotification() {
        unfairLock.withLock {
            self.hasEnqueuedNotification = false

            // Notify after delay.
            self.lastNotificationDate = Date()
            notifyQueue.async {
                self.notifyBlock()
            }
        }
    }
}
