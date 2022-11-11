//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class Batching: NSObject {
    @objc
    public static let kDefaultBatchSize: UInt = 1000

    // Break loop cycles into batches, releasing stale objects
    // after each batch to avoid out of memory errors.
    //
    // If batchSize == 0, no batching is done and no
    // autoreleasepool is used.
    public static func loop(batchSize: UInt,
                            loopBlock: (UnsafeMutablePointer<ObjCBool>) throws -> Void) rethrows {
        var stop: ObjCBool = false
        guard batchSize > 0 else {
            // No batching.
            while !stop.boolValue {
                try loopBlock(&stop)
            }
            return
        }

        // With batching.
        while !stop.boolValue {
            try autoreleasepool {
                for _ in 0..<batchSize {
                    guard !stop.boolValue else {
                        return
                    }
                    try loopBlock(&stop)
                }
            }
        }
    }

    @objc
    public static func loopObjc(batchSize: UInt,
                                loopBlock: (UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop: ObjCBool = false
        guard batchSize > 0 else {
            // No batching.
            while !stop.boolValue {
                loopBlock(&stop)
            }
            return
        }

        // With batching.
        var batchIndex = 0
        while !stop.boolValue {
            if batchIndex > 0 {
                Logger.verbose("batch: \(batchIndex)")
            }
            autoreleasepool {
                for _ in 0..<batchSize {
                    guard !stop.boolValue else {
                        return
                    }
                    loopBlock(&stop)
                }
            }
            batchIndex += 1
        }
    }
}

// MARK: -

extension Batching {
    @objc(enumerateArray:batchSize:itemBlock:)
    @available(swift, obsoleted: 1.0)
    public static func enumerate(array: [AnyObject],
                                 batchSize: UInt,
                                 itemBlock: (AnyObject) -> Void) {
        Self.enumerate(array, batchSize: batchSize, itemBlock: itemBlock)
    }

    public static func enumerate<T>(_ array: [T],
                                    batchSize: UInt,
                                    itemBlock: (T) throws -> Void) rethrows {
        var index: Int = 0
        try Self.loop(batchSize: batchSize) { stop in
            guard index < array.count else {
                stop.pointee = true
                return
            }
            guard let item = array[safe: index] else {
                owsFailDebug("Missing item.")
                stop.pointee = true
                return
            }
            try itemBlock(item)
            index += 1
        }
    }
}
