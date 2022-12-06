//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import zlib

public struct CRC32 {
    private var rawValue: uLong

    public var value: UInt32 { UInt32(rawValue) }

    public init() {
        self.init(rawValue: 0)
    }

    private init(rawValue: uLong) {
        self.rawValue = rawValue
    }

    public func update(with data: Data) -> CRC32 {
        let newRawValue = data.withUnsafeBytes { bytes -> uLong in
            let pointerForC = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return crc32(self.rawValue, pointerForC, UInt32(bytes.count))
        }
        return CRC32(rawValue: newRawValue)
    }
}
