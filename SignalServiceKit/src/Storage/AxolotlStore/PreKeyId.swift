//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class PreKeyId: NSObject {
    private enum Constants {
        static let upperBound: UInt32 = 0x1000000
    }

    static func random() -> UInt32 {
        return UInt32.random(in: 1..<Constants.upperBound)
    }

    @objc
    static func nextPreKeyId(lastPreKeyId: UInt32, minimumCapacity: UInt32) -> UInt32 {
        guard (1..<Constants.upperBound).contains(lastPreKeyId) else {
            return UInt32.random(in: 1...(Constants.upperBound - minimumCapacity))
        }
        // We need `minimumCapacity` *after* `lastPreKeyId`.
        if lastPreKeyId + minimumCapacity < Constants.upperBound {
            return lastPreKeyId + 1
        }
        return 1
    }
}
