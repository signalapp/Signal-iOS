//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PromiseNamespace { case promise }

extension DispatchQueue: Scheduler {

    public func async(_ work: @escaping () -> Void) {
        self.async(execute: work)
    }

    public func sync<T>(_ work: () -> T) -> T {
        return self.sync(execute: work)
    }

    public func sync<T>(_ work: () throws -> T) rethrows -> T {
        return try self.sync(execute: work)
    }

    public func asyncAfter(deadline: DispatchTime, _ work: @escaping () -> Void) {
        self.asyncAfter(deadline: deadline, execute: work)
    }

    public func asyncAfter(wallDeadline: DispatchWallTime, _ work: @escaping () -> Void) {
        self.asyncAfter(wallDeadline: wallDeadline, execute: work)
    }

    public func asyncIfNecessary(execute work: @escaping () -> Void) {
        if DispatchQueueIsCurrentQueue(self), _CurrentStackUsage() < 0.8 {
            work()
        } else {
            async { work() }
        }
    }
}
