//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

final public class ChunkedOutputStreamTransform: StreamTransform {

    public func transform(data: Data) throws -> Data {
        let byteLength = UInt32(data.count)
        var result = Data()
        result.append(Self.writeVariableLengthUInt32(byteLength))
        result.append(data)
        return result
    }

    public static func writeVariableLengthUInt32(_ value: UInt32) -> Data {
        var result = Data()
        var v = value
        while v > 0x7F {
            result.append(contentsOf: [(UInt8(v & 0x7f | 0x80))])
            v >>= 7
        }
        result.append(contentsOf: [UInt8(v)])
        return result
    }
}
