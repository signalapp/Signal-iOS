//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

/// Returns a single `TestScheduler` for all schedulers instances,
/// for the purposes of testing.
/// Makes it possible to turn asynchronous production code
/// into fully synchronous tests. See `TestScheduler` for more documentation.
public class TestSchedulers: Schedulers {

    public let scheduler: TestScheduler

    public init(scheduler: TestScheduler) {
        self.scheduler = scheduler
    }

    public var sync: Scheduler { scheduler }

    public var main: Scheduler { scheduler }

    public var sharedUserInteractive: Scheduler { scheduler }

    public var sharedUserInitiated: Scheduler { scheduler }

    public var sharedUtility: Scheduler { scheduler }

    public var sharedBackground: Scheduler { scheduler }

    public func sharedQueue(at qos: DispatchQoS) -> Scheduler {
        return scheduler
    }

    public func global(qos: DispatchQoS.QoSClass) -> Scheduler {
        return scheduler
    }
}
