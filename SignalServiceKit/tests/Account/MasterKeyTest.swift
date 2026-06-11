//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct MasterKeyTest {
    @Test
    func testCodable() throws {
        let masterKey = try MasterKey(data: Data(repeating: 17, count: 32))
        let encodedValue = try JSONEncoder().encode(masterKey)
        #expect(String(data: encodedValue, encoding: .utf8) == #"{"masterKey":"ERERERERERERERERERERERERERERERERERERERERERE="}"#)
        let decodedValue = try JSONDecoder().decode(MasterKey.self, from: encodedValue)
        #expect(decodedValue.rawData == masterKey.rawData)
    }

    @Test(arguments: [
        #"{}"#,
        // These cases currently produce a valid MasterKey but shouldn't:
        // #"{"masterKey":""}"#,
        // #"{"masterKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="}"#,
        // #"{"masterKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}"#,
    ])
    func testCodableMalformed(encodedValue: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MasterKey.self, from: Data(encodedValue.utf8))
        }
    }

    @Test
    func testDerivedKeys() throws {
        let masterKey = try MasterKey(data: Data(repeating: 42, count: 32))
        #expect(masterKey.data(for: .loggingKey).canonicalStringRepresentation == "cd2a39f4857de4df3fe793d1de061bfa3dd63533c0a4ef79b3fa3eba2bf96e62")
        #expect(masterKey.data(for: .registrationLock).canonicalStringRepresentation == "3a40e25812e6c20cca76a602451dd2bc7484553514438cade320c2aef54e10d1")
        #expect(masterKey.data(for: .registrationRecoveryPassword).canonicalStringRepresentation == "kflZz+45Z23t0Ci8i7vR6R/6akLFd1TQlf6Kvn8NT1Y=")
        #expect(masterKey.data(for: .storageService).canonicalStringRepresentation == "PzG2GBcqn4rUXikHiOYXZzbmFh1OoOgFD4VTUh9ZwgA=")
        #expect(masterKey.data(for: .storageServiceManifest(version: 1)).canonicalStringRepresentation == "4Bm2DQtPJqmIJ6BvByPuWJmRTb4BS9fCXssU7nSr6a8=")
        #expect(masterKey.data(for: .storageServiceManifest(version: 10)).canonicalStringRepresentation == "ccSiHKl53x+5DtWmVtYmJZkfqRXCKbCjQ02+MW8dYN4=")
        #expect(masterKey.data(for: .legacy_storageServiceRecord(identifier: StorageService.StorageIdentifier(
            data: Data(repeating: 1, count: 16),
            type: .account,
        ))).canonicalStringRepresentation == "3F9GA+ppdf4OV1GfD3ntUZyxAh4FPyUoHSpzRztwv1s=")
        #expect(masterKey.data(for: .legacy_storageServiceRecord(identifier: StorageService.StorageIdentifier(
            data: Data(repeating: 2, count: 16),
            type: .account,
        ))).canonicalStringRepresentation == "HZ+2K/BmhiF0JaWt9z/PrBAzo18kd3GoguRmg9U3F+0=")
        #expect(masterKey.data(for: .legacy_storageServiceRecord(identifier: StorageService.StorageIdentifier(
            data: Data(repeating: 1, count: 16),
            type: .contact,
        ))).canonicalStringRepresentation == "3F9GA+ppdf4OV1GfD3ntUZyxAh4FPyUoHSpzRztwv1s=")
    }
}
