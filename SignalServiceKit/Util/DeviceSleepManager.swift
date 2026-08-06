//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class DeviceSleepBlockObject {
    public let blockReason: String
    public init(blockReason: String) {
        self.blockReason = blockReason
    }
}

@MainActor
public protocol DeviceSleepManager {
    func addBlock(blockObject: DeviceSleepBlockObject)
    func removeBlock(blockObject: DeviceSleepBlockObject)
}

extension DeviceSleepManager {

    /// Listens to the given `updateStream`, calling `onUpdate` for each
    /// element. Blocks sleep for a given update if `onUpdate` returns true.
    public func manageBlockForUpdateStream<T>(
        _ updateStream: AsyncStream<T>,
        label: String,
        onUpdate: (T) -> Bool,
    ) async {
        // Retained in-memory here as long as the update stream is running.
        var deviceSleepBlock: DeviceSleepBlockObject?

        for await update in updateStream {
            let shouldBlockSleep = onUpdate(update)

            if shouldBlockSleep {
                deviceSleepBlock = deviceSleepBlock ?? {
                    let newSleepBlock = DeviceSleepBlockObject(blockReason: label)
                    addBlock(blockObject: newSleepBlock)
                    return newSleepBlock
                }()
            } else {
                deviceSleepBlock
                    .take()
                    .map { removeBlock(blockObject: $0) }
            }
        }

        if let deviceSleepBlock {
            removeBlock(blockObject: deviceSleepBlock)
        }
    }
}

#if TESTABLE_BUILD

class DeviceSleepManagerMock: DeviceSleepManager {
    func addBlock(blockObject: DeviceSleepBlockObject) {}
    func removeBlock(blockObject: DeviceSleepBlockObject) {}
}

#endif
