//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum DebouncedEventMode {
    /// "Wait before firing in case requests come in quick succession."
    ///
    /// This mode *always* fires after a delay, and it ignores "redundant"
    /// requests that occur while a delayed event is already enqueued.
    ///
    /// This is useful when the timeliness of the "first" request does _not_
    /// matter.
    ///
    /// Assuming maxFrequencySeconds = 5:
    ///
    /// Second  1: A -> Enqueues Delayed Fire
    /// Second  2: B    (de-bounced)
    /// Second  4: C    (de-bounced)
    /// Second  6:      Event Fires for A, B, C (maxFrequencySeconds after first delayed request A)
    /// Second  8: D -> Enqueues Delayed Fire
    /// Second  9: E    (de-bounced)
    /// Second 13:      Event Fires for D, E (maxFrequencySeconds after first delayed request D)
    /// Second 20: F -> Enqueues Delayed Fire
    /// Second 25:      Event Fires for F (maxFrequencySeconds after first delayed request F)
    case lastOnly

    /// "Delay firing if we've fired recently, but always fire eventually."
    ///
    /// This mode will fire immediately when the first event arrives, but it
    /// will delay subsequent events for up to maxFrequencySeconds.
    ///
    /// This is useful when the latency of the first request is important. It's
    /// also useful if you expect events to be "rare" but want to guard against
    /// sudden bursts.
    ///
    /// Assuming maxFrequencySeconds = 5:
    ///
    /// Second  1: A -> Event Fires Immediately
    /// Second  2: B -> Enqueues Delayed Fire
    /// Second  4: C    (de-bounced)
    /// Second  6:      Event Fires for B, C (maxFrequencySeconds after A fired)
    /// Second  8: D -> Enqueues Delayed Fire
    /// Second  9: E    (de-bounced)
    /// Second 11:      Event Fires for D, E (maxFrequencySeconds after B, C fired)
    /// Second 20: F -> Event Fires Immediately (because 20 - 11 >= maxFrequencySeconds)
    case firstLast
}

// MARK: -

/// Invokes a "notification" block in response to "notification requests",
/// but no more often than every N seconds.
public protocol DebouncedEvent {
    func requestNotify()
}

// MARK: -

public enum DebouncedEvents {
    // A very small interval.
    public static let thetaInterval: Double = 0.001

    public static func build(
        mode: DebouncedEventMode,
        maxFrequencySeconds: TimeInterval,
        onQueue queue: DispatchQueue,
        notifyBlock: @escaping () -> Void,
    ) -> DebouncedEvent {
        switch mode {
        case .lastOnly:
            return DebouncedEventLastOnly(
                maxFrequencySeconds: maxFrequencySeconds,
                onQueue: queue,
                notifyBlock: notifyBlock,
            )
        case .firstLast:
            return DebouncedEventFirstLast(
                maxFrequencySeconds: maxFrequencySeconds,
                onQueue: queue,
                notifyBlock: notifyBlock,
            )
        }
    }
}

// MARK: -

/// See comments on DebouncedEventMode.
private class DebouncedEventLastOnly: DebouncedEvent {
    private var hasEnqueuedNotification = false
    private let maxFrequencySeconds: TimeInterval
    private let notifyBlock: () -> Void
    private let queue: DispatchQueue
    private let unfairLock = UnfairLock()

    init(
        maxFrequencySeconds: TimeInterval,
        onQueue queue: DispatchQueue,
        notifyBlock: @escaping () -> Void,
    ) {
        self.maxFrequencySeconds = maxFrequencySeconds
        self.queue = queue
        self.notifyBlock = notifyBlock
    }

    func requestNotify() {
        unfairLock.withLock {
            if hasEnqueuedNotification {
                // Delayed notification is already enqueued. We can ignore this request
                // (de-bounce).
                return
            }
            // We've notified recently; wait before notifying again.
            self.hasEnqueuedNotification = true
            if self.maxFrequencySeconds > DebouncedEvents.thetaInterval {
                self.queue.asyncAfter(deadline: DispatchTime.now() + self.maxFrequencySeconds) {
                    self.fireDelayedNotification()
                }
            } else {
                // For sufficiently small frequencies, dispatch without asyncAfter();
                // DispatchQueue.async() is much less vulnerable to delays.
                self.queue.async {
                    self.fireDelayedNotification()
                }
            }
        }
    }

    private func fireDelayedNotification() {
        unfairLock.withLock {
            owsAssertDebug(self.hasEnqueuedNotification)
            self.hasEnqueuedNotification = false
        }
        notifyBlock()
    }
}

// MARK: -

// See comments on DebouncedEventMode.
private class DebouncedEventFirstLast: DebouncedEvent {
    private var hasEnqueuedNotification = false
    private var lastNotificationDate: MonotonicDate?
    private let maxFrequencySeconds: TimeInterval
    private let notifyBlock: () -> Void
    private let queue: DispatchQueue
    private let unfairLock = UnfairLock()

    init(
        maxFrequencySeconds: TimeInterval,
        onQueue queue: DispatchQueue,
        notifyBlock: @escaping () -> Void,
    ) {
        self.maxFrequencySeconds = maxFrequencySeconds
        self.queue = queue
        self.notifyBlock = notifyBlock
    }

    func requestNotify() {
        unfairLock.withLock {
            if hasEnqueuedNotification {
                // Delayed notification is already enqueued. We can ignore this request
                // (de-bounce).
                return
            }
            self.hasEnqueuedNotification = true

            let now = MonotonicDate()
            let earliestAllowedDate = lastNotificationDate?.adding(self.maxFrequencySeconds)
            if let earliestAllowedDate, now < earliestAllowedDate {
                self.queue.asyncAfter(deadline: DispatchTime.now() + .nanoseconds(Int((earliestAllowedDate - now).nanoseconds))) {
                    self.fireDelayedNotification()
                }
            } else {
                self.queue.async {
                    self.fireDelayedNotification()
                }
            }
        }
    }

    private func fireDelayedNotification() {
        unfairLock.withLock {
            owsAssertDebug(self.hasEnqueuedNotification)
            self.hasEnqueuedNotification = false
            self.lastNotificationDate = MonotonicDate()
        }
        notifyBlock()
    }
}
