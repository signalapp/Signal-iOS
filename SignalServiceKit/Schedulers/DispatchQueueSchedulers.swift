//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class DispatchQueueSchedulers: Schedulers {

    public init() {}

    public let sync: Scheduler = SyncScheduler()

    public var main: Scheduler {
        return DispatchQueue.main
    }

    public func global(qos: DispatchQoS.QoSClass) -> Scheduler {
        return DispatchQueue.global(qos: qos)
    }

    public var sharedUserInteractive: Scheduler {
        return DispatchQueue.sharedUserInteractive
    }

    public var sharedUserInitiated: Scheduler {
        return DispatchQueue.sharedUserInitiated
    }

    public var sharedUtility: Scheduler {
        return DispatchQueue.sharedUtility
    }

    public var sharedBackground: Scheduler {
        return DispatchQueue.sharedBackground
    }

    public func sharedQueue(at qos: DispatchQoS) -> Scheduler {
        return DispatchQueue.sharedQueue(at: qos)
    }

    public func queue(
        label: String,
        qos: DispatchQoS,
        attributes: DispatchQueue.Attributes,
        autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency,
        target: DispatchQueue?
    ) -> Scheduler {
        return DispatchQueue(
            label: label,
            qos: qos,
            attributes: attributes,
            autoreleaseFrequency: autoreleaseFrequency,
            target: target
        )
    }
}
