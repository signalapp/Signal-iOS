//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class LocalDevice: NSObject {
    @objc
    public static var allCoreCount: Int {
        // iOS can shut down cores, so we consult activeProcessorCount,
        // not processorCount.
        ProcessInfo.processInfo.processorCount
    }

    @objc
    public static var activeCoreCount: Int {
        // iOS can shut down cores, so we consult activeProcessorCount,
        // not processorCount.
        ProcessInfo.processInfo.activeProcessorCount
    }

    @objc
    public static var offMainCoreCount: UInt {
        // When working off the main thread, we want to avoid spawning
        // so many threads that we affect the main thread. Therefore
        // in any place that we control fan out (e.g. OperationQueue,
        // GCDQueueCluster, etc.) we limit concurrency to the number of
        // active cores less one.

        UInt(max(1, activeCoreCount - 1))
    }
}
