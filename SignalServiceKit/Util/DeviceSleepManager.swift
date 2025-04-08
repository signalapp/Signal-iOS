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
