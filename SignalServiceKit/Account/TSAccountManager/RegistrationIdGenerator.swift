//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Generates registration IDs. Often no need to stub out in tests;
/// just a random number generator with defined bounds.
/// Use mock only to grab IDs that are generated.
public class RegistrationIdGenerator {

    public init() {}

    public static func generate() -> UInt32 {
        return UInt32.random(in: 1...0x3fff)
    }

    public func generate() -> UInt32 {
        return Self.generate()
    }
}

#if TESTABLE_BUILD

public class MockRegistrationIdGenerator: RegistrationIdGenerator {

    public var generatedRegistrationIds: [UInt32] = []

    override public func generate() -> UInt32 {
        let value = Self.generate()
        generatedRegistrationIds.append(value)
        return value
    }
}

#endif
