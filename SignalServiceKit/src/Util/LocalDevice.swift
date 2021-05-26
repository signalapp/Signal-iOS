//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class LocalDevice: NSObject {
    @objc
    public static var allCoreCount: Int {
        ProcessInfo.processInfo.processorCount
    }

    @objc
    public static var activeCoreCount: Int {
        // iOS can shut down cores, so we consult activeProcessorCount,
        // not processorCount.
        ProcessInfo.processInfo.activeProcessorCount
    }
}
