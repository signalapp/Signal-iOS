//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Consider a DebouncedEvent with maxFrequencySeconds of 5.
//
// The event receives requests in the following order:
//
// Second 1:  A
// Second 2:  B
// Second 4:  C
// Second 8:  D
// Second 9:  E
// Second 20: F
public enum DebouncedEventMode {
    // "Ignore requests if the event has fired recently."
    //
    // .firstOnly will fire immediately if it has not fired in the last
    // maxFrequencySeconds; otherwise it will ignore the request.
    //
    // Second 1:  A -> Event Fires Immediately
    // Second 2:  B    (de-bounced)
    // Second 4:  C    (de-bounced)
    // Second 8:  D -> Event Fires Immediately
    // Second 9:  E    (de-bounced)
    // Second 20: F -> Event Fires Immediately
    //
    // .firstOnly is appropriate when we want to throttle frequent events and:
    //
    // * Timeliness of "first" request matters.
    // * "Last" requests can be safely discarded.
    // * We need to ensure the event never fires more often than once 1/maxFrequencySeconds.
    // * .firstOnly and .lastOnly will fire less often than .firstLast.
    case firstOnly

    // "Wait before firing in case requests come in quick succession."
    //
    // .lastOnly fires delay events and ignores "redundant" requests
    // that occur while a delayed event is already enqueued.
    //
    // Second  1: A -> Enqueues Delayed Fire
    // Second  2: B    (de-bounced)
    // Second  4: C    (de-bounced)
    // Second  6:      Event Fires for A, B, C (maxFrequencySeconds after first delayed request A)
    // Second  8: D -> Enqueues Delayed Fire
    // Second  9: E    (de-bounced)
    // Second 13:      Event Fires for D, E (maxFrequencySeconds after first delayed request D)
    // Second 20: F -> Enqueues Delayed Fire
    // Second 25:      Event Fires for F (maxFrequencySeconds after first delayed request F)
    //
    // .lastOnly is appropriate when we want to throttle frequent events and:
    //
    // * Timeliness of "first" request does _not_ matter.
    // * "Last" requests cannot be safely discarded (e.g. B does work that A would not do).
    // * We need to ensure the event never fires more often than once 1/maxFrequencySeconds.
    // * .firstOnly and .lastOnly will fire less often than .firstLast.
    case lastOnly

    // "Delay firing if we've fired recently, but always fire eventually."
    //
    // .firstLast will fire immediately if has not fired in the last
    // maxFrequencySeconds; otherwise it will delay until maxFrequencySeconds
    // has passed.
    //
    // Second  1: A -> Event Fires Immediately
    // Second  2: B -> Enqueues Delayed Fire
    // Second  4: C    (de-bounced)
    // Second  7:      Event Fires for A, B, C (maxFrequencySeconds after first delayed request B)
    // Second  8: D -> Enqueues Delayed Fire
    // Second  9: E    (de-bounced)
    // Second 13:      Event Fires for D, E (maxFrequencySeconds after first delayed request D)
    // Second 20: F -> Event Fires Immediately
    //
    // .firstLast is appropriate when we want to throttle frequent events and:
    //
    // * Timeliness of "first" request matters.
    // * "Last" requests cannot be safely discarded (e.g. B does work that A would not do).
    // * We need to ensure the event never fires more often than once 1/maxFrequencySeconds.
    // * firstLast will fire more often than .firstOnly and .lastOnly.
    case firstLast
}

// MARK: -

// Invokes a "notification" block in response to
// "notification requests", but no more often than every N
// seconds.
public protocol DebouncedEvent {
    func requestNotify()
}

// MARK: -

public class DebouncedEvents {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private init() {}

    // A very small interval.
    public static let thetaInterval: Double = 0.001

    public static func build(mode: DebouncedEventMode,
                             maxFrequencySeconds: TimeInterval,
                             onQueue queueBehavior: DebouncedEventQueueBehavior,
                             notifyBlock: @escaping () -> Void) -> DebouncedEvent {
        switch mode {
        case .firstOnly:
            return DebouncedEventFirstOnly(maxFrequencySeconds: maxFrequencySeconds,
                                           onQueue: queueBehavior,
                                           notifyBlock: notifyBlock)
        case .lastOnly:
            return DebouncedEventLastOnly(maxFrequencySeconds: maxFrequencySeconds,
                                          onQueue: queueBehavior,
                                           notifyBlock: notifyBlock)
        case .firstLast:
            return DebouncedEventFirstLast(maxFrequencySeconds: maxFrequencySeconds,
                                           onQueue: queueBehavior,
                                           notifyBlock: notifyBlock)
        }
    }
}

// MARK: -

// See comments on DebouncedEventMode.
private class DebouncedEventFirstOnly: NSObject, DebouncedEvent {
    private var lastNotificationDate: Date?
    private let maxFrequencySeconds: TimeInterval
    private let notifyBlock: () -> Void
    private let queueBehavior: DebouncedEventQueueBehavior
    private let unfairLock = UnfairLock()

    public required init(maxFrequencySeconds: TimeInterval,
                         onQueue queueBehavior: DebouncedEventQueueBehavior,
                         notifyBlock: @escaping () -> Void) {
        self.maxFrequencySeconds = maxFrequencySeconds
        self.queueBehavior = queueBehavior
        self.notifyBlock = notifyBlock
    }

    public func requestNotify() {
        let shouldFire: Bool = unfairLock.withLock {
            let shouldFire: Bool = {
                guard let lastNotificationDate = self.lastNotificationDate else {
                    return true
                }
                return abs(lastNotificationDate.timeIntervalSinceNow) >= self.maxFrequencySeconds
            }()
            guard shouldFire else {
                // We've notified recently; wait before notifying again.
                // We can ignore this request (de-bounce).
                return false
            }
            self.lastNotificationDate = Date()
            return true
        }

        if shouldFire {
            queueBehavior.fire(block: notifyBlock)
        }
    }
}

// MARK: -

// See comments on DebouncedEventMode.
private class DebouncedEventLastOnly: NSObject, DebouncedEvent {
    private var hasEnqueuedNotification = false
    private let maxFrequencySeconds: TimeInterval
    private let notifyBlock: () -> Void
    private let queueBehavior: DebouncedEventQueueBehavior
    private let unfairLock = UnfairLock()

    public required init(maxFrequencySeconds: TimeInterval,
                         onQueue queueBehavior: DebouncedEventQueueBehavior,
                         notifyBlock: @escaping () -> Void) {
        self.maxFrequencySeconds = maxFrequencySeconds
        self.queueBehavior = queueBehavior
        self.notifyBlock = notifyBlock
    }

    public func requestNotify() {
        unfairLock.withLock {
            if hasEnqueuedNotification {
                // Delayed notification is already enqueued.
                // We can ignore this request (de-bounce).
                return
            }
            // We've notified recently; wait before notifying again.
            self.hasEnqueuedNotification = true
            if self.maxFrequencySeconds > DebouncedEvents.thetaInterval {
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + self.maxFrequencySeconds) { [weak self] in
                    self?.fireDelayedNotification()
                }
            } else {
                // For sufficiently small frequencies, dispatch without asyncAfter();
                // DispatchQueue.async() is much less vulnerable to delays.
                DispatchQueue.global().async { [weak self] in
                    self?.fireDelayedNotification()
                }
            }
        }
    }

    private func fireDelayedNotification() {
        unfairLock.withLock {
            owsAssertDebug(self.hasEnqueuedNotification)
            self.hasEnqueuedNotification = false
        }

        queueBehavior.fire(block: notifyBlock)
    }
}

// MARK: -

// See comments on DebouncedEventMode.
private class DebouncedEventFirstLast: NSObject, DebouncedEvent {
    private var hasEnqueuedNotification = false
    private var lastNotificationDate: Date?
    private let maxFrequencySeconds: TimeInterval
    private let notifyBlock: () -> Void
    private let queueBehavior: DebouncedEventQueueBehavior
    private let unfairLock = UnfairLock()

    public required init(maxFrequencySeconds: TimeInterval,
                         onQueue queueBehavior: DebouncedEventQueueBehavior,
                         notifyBlock: @escaping () -> Void) {
        self.maxFrequencySeconds = maxFrequencySeconds
        self.queueBehavior = queueBehavior
        self.notifyBlock = notifyBlock
    }

    public func requestNotify() {
        let shouldFire: Bool = unfairLock.withLock {
            if hasEnqueuedNotification {
                // Delayed notification is already enqueued.
                // We can ignore this request (de-bounce).
                return false
            }
            if let lastNotificationDate = self.lastNotificationDate {
                let elapsed = abs(lastNotificationDate.timeIntervalSinceNow)
                let timerDelay = self.maxFrequencySeconds - elapsed
                if timerDelay > 0 {
                    // We've notified recently; wait before notifying again.
                    self.hasEnqueuedNotification = true
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + timerDelay) { [weak self] in
                        self?.fireDelayedNotification()
                    }
                    return false
                }
            }

            // Notify immediately.
            self.lastNotificationDate = Date()
            return true
        }

        if shouldFire {
            queueBehavior.fire(block: notifyBlock)
        }
    }

    private func fireDelayedNotification() {
        unfairLock.withLock {
            owsAssertDebug(self.hasEnqueuedNotification)
            self.hasEnqueuedNotification = false
            self.lastNotificationDate = Date()
        }

        queueBehavior.fire(block: notifyBlock)
    }
}

// MARK: -

public enum DebouncedEventQueueBehavior {
    case syncOnRequestingQueue
    case asyncOnQueue(queue: DispatchQueue)

    func fire(block: @escaping () -> Void) {
        switch self {
        case .syncOnRequestingQueue:
            block()
        case .asyncOnQueue(let queue):
            queue.async {
                block()
            }
        }
    }
}
