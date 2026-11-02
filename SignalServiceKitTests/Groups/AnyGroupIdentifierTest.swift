//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct AnyGroupIdentifierTest {
    @Test(arguments: [
        Data(count: 16),
        Data(repeating: 1, count: 16),
        Data(count: 32),
        Data(repeating: 2, count: 32),
    ])
    func testValid(groupIdData: Data) throws {
        let groupId = try AnyGroupIdentifier.parseFrom(groupIdData)
        #expect(groupId.serialize() == groupIdData)
    }

    @Test(arguments: [
        Data(),
        Data(count: 15),
        Data(count: 17),
        Data(count: 31),
        Data(count: 33),
    ])
    func testInvalid(groupIdData: Data) {
        #expect(throws: Error.self) {
            try AnyGroupIdentifier.parseFrom(groupIdData)
        }
    }

    @Test(arguments: [
        Data(count: 16),
        Data(repeating: 3, count: 16),
    ])
    func testGV1Valid(groupIdData: Data) throws {
        let groupId = try GroupIdentifierV1(rawValue: groupIdData)
        #expect(groupId.rawValue == groupIdData)
    }

    @Test(arguments: [
        Data(count: 32),
    ])
    func testGV1Invalid(groupIdData: Data) {
        #expect(throws: Error.self) {
            try GroupIdentifierV1(rawValue: groupIdData)
        }
    }
}
