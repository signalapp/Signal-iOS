//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// A thread-safe timer that runs on a specific queue and which
// can be safely created, invalidated or deallocated on any thread.
public class OffMainThreadTimer {

    private let timeInterval: TimeInterval
    private let repeats: Bool
    private let queue: DispatchQueue

    public typealias Block = (OffMainThreadTimer) -> Void
    private let block: Block

    private let _isValid = AtomicBool(true)
    public var isValid: Bool {
        get { _isValid.get() }
        set { _isValid.set(newValue) }
    }

    public required init(timeInterval: TimeInterval,
                         repeats: Bool,
                         queue: DispatchQueue = .global(),
                         _ block: @escaping Block) {
        owsAssertDebug(timeInterval > 0)

        self.timeInterval = max(0, timeInterval)
        self.repeats = repeats
        self.queue = queue
        self.block = block

        scheduleNextFire()
    }

    private func scheduleNextFire() {
        queue.asyncAfter(deadline: .now() + timeInterval) { [weak self] in
            self?.fire()
        }
    }

    private func fire() {
        assertOnQueue(queue)
        guard self.isValid else {
            return
        }
        block(self)
        guard repeats else {
            invalidate()
            return
        }
        scheduleNextFire()
    }

    deinit {
        invalidate()
    }

    public func invalidate() {
        isValid = false
    }
}
