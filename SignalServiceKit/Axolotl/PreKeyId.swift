//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum PreKeyId {
    private enum Constants {
        static let upperBound: UInt32 = 0x1000000
    }

    static func random() -> UInt32 {
        return UInt32.random(in: 1..<Constants.upperBound)
    }

    static func nextPreKeyIds(lastPreKeyId: UInt32?, count: Int) -> ClosedRange<UInt32> {
        owsPrecondition(count >= 1)
        let result = nextPreKeyId(lastPreKeyId: lastPreKeyId, count: count)
        return result...(result.advanced(by: count - 1))
    }

    private static func nextPreKeyId(lastPreKeyId: UInt32?, count: Int) -> UInt32 {
        guard let lastPreKeyId, (1..<Constants.upperBound).contains(lastPreKeyId) else {
            return UInt32.random(in: 1...(Constants.upperBound - UInt32(count)))
        }
        // We need `minimumCapacity` *after* `lastPreKeyId`.
        if lastPreKeyId + UInt32(count) < Constants.upperBound {
            return lastPreKeyId + 1
        }
        return 1
    }
}
