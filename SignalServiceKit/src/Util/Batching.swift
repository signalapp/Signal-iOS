//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class Batching: NSObject {
    @objc
    public static let kDefaultBatchSize: UInt = 10 * 1000

    // Break loop cycles into batches, releasing stale objects
    // after each batch to avoid out of memory errors.
    //
    // If batchSize == 0, no batching is done and no
    // autoreleasepool is used.
    public static func loop(batchSize: UInt,
                            conditionBlock: () -> Bool,
                            loopBlock: () throws -> Void) throws {
        guard batchSize > 0 else {
            // No batching.
            while true {
                guard conditionBlock() else {
                    return
                }
                try loopBlock()
            }
        }

        // With batching.
        while true {
            try autoreleasepool {
                for _ in 0..<batchSize {
                    guard conditionBlock() else {
                        return
                    }
                    try loopBlock()
                }
            }
        }
    }

    @objc
    public static func loopObjc(batchSize: UInt,
                                conditionBlock: () -> Bool,
                                loopBlock: () -> Void) {
        guard batchSize > 0 else {
            // No batching.
            while true {
                guard conditionBlock() else {
                    return
                }
                loopBlock()
            }
        }

        // With batching.
        while true {
            autoreleasepool {
                for _ in 0..<batchSize {
                    guard conditionBlock() else {
                        return
                    }
                    loopBlock()
                }
            }
        }
    }
}
