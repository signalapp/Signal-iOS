//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

/// Scheduler that always runs any work on the current thread, synchronously.
/// Useful if you don't care what thread your work runs on, and want to
/// incur the least overhead.
/// Should NOT be used for scheduled methods, e.g.:
/// `promise.after(seconds: 10, on: SyncScheduler()`
/// would be a bad form, and fall back to scheduling in the future on the main thread.
public class SyncScheduler: Scheduler {

    public init() {}

    public func async(_ work: @escaping () -> Void) {
        work()
    }

    public func sync(_ work: @escaping () -> Void) {
        work()
    }

    public func sync<T>(_ work: @escaping () -> T) -> T {
        return work()
    }

    public func asyncAfter(deadline: DispatchTime, _ work: @escaping () -> Void) {
        owsFailDebug("Should not schedule on async queue. Using main queue instead.")
        DispatchQueue.main.asyncAfter(deadline: deadline, work)
    }

    public func asyncAfter(wallDeadline: DispatchWallTime, _ work: @escaping () -> Void) {
        owsFailDebug("Should not schedule on async queue. Using main queue instead.")
        DispatchQueue.main.asyncAfter(wallDeadline: wallDeadline, work)
    }

    public func asyncIfNecessary(execute work: @escaping () -> Void) {
        work()
    }
}
