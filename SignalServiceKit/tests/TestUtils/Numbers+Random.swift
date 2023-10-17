//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension UInt64 {
    static var maxRandom: UInt64 { UInt64.random(in: 0...UInt64.max) }
    static var maxRandomInt64Compat: UInt64 { UInt64(Int64.maxRandom) }
}

extension Int64 {
    static var maxRandom: Int64 { Int64.random(in: 0...Int64.max) }
}
