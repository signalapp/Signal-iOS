//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum Batching {
    public static let kDefaultBatchSize: UInt = 1000

    // Break loop cycles into batches, releasing stale objects
    // after each batch to avoid out of memory errors.
    //
    // If batchSize == 0, no batching is done and no
    // autoreleasepool is used.
    public static func loop(
        batchSize: UInt,
        loopBlock: (_ stop: inout Bool) throws -> Void,
    ) rethrows {
        var stop = false
        guard batchSize > 0 else {
            // No batching.
            while !stop {
                try loopBlock(&stop)
            }
            return
        }

        // With batching.
        while !stop {
            try autoreleasepool {
                for _ in 0..<batchSize {
                    guard !stop else {
                        return
                    }
                    try loopBlock(&stop)
                }
            }
        }
    }
}
