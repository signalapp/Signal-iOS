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
        #expect(String(data: encodedValue, encoding: .utf8) == #""ERERERERERERERERERERERERERERERERERERERERERE=""#)
        let decodedValue = try JSONDecoder().decode(MasterKey.self, from: encodedValue)
        #expect(decodedValue.rawData == masterKey.rawData)
    }

    @Test
    func testDeprecatedCodable() throws {
        let masterKey = try MasterKey(data: Data(repeating: 17, count: 32))
        let deprecatedMasterKey = DeprecatedMasterKey(masterKey: masterKey)
        let encodedValue = try JSONEncoder().encode(deprecatedMasterKey)
        #expect(String(data: encodedValue, encoding: .utf8) == #"{"masterKey":"ERERERERERERERERERERERERERERERERERERERERERE="}"#)
        let decodedValue = try JSONDecoder().decode(DeprecatedMasterKey.self, from: encodedValue)
        #expect(decodedValue.masterKey.rawData == masterKey.rawData)
    }

    @Test(arguments: [
        #""""#,
        #""AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==""#,
        #""AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA""#,
    ])
    func testCodableMalformed(encodedValue: String) {
        #expect(throws: Error.self) {
            try JSONDecoder().decode(MasterKey.self, from: Data(encodedValue.utf8))
        }
    }

    @Test(arguments: [
        #"{}"#,
        #"{"masterKey":""}"#,
        #"{"masterKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="}"#,
        #"{"masterKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}"#,
    ])
    func testDeprecatedCodableMalformed(encodedValue: String) {
        #expect(throws: Error.self) {
            try JSONDecoder().decode(DeprecatedMasterKey.self, from: Data(encodedValue.utf8))
        }
    }

    @Test
    func testDerivedKeys() throws {
        let masterKey = try MasterKey(data: Data(repeating: 42, count: 32))
        #expect(masterKey.deriveLoggingKey().rawData.hexadecimalString == "cd2a39f4857de4df3fe793d1de061bfa3dd63533c0a4ef79b3fa3eba2bf96e62")
        #expect(masterKey.deriveRegistrationLock().canonicalStringRepresentation == "3a40e25812e6c20cca76a602451dd2bc7484553514438cade320c2aef54e10d1")
        #expect(masterKey.deriveRegistrationRecoveryPassword().canonicalStringRepresentation == "kflZz+45Z23t0Ci8i7vR6R/6akLFd1TQlf6Kvn8NT1Y=")
        let storageServiceKey = masterKey.deriveStorageServiceKey()
        #expect(storageServiceKey.rawData.base64EncodedString() == "PzG2GBcqn4rUXikHiOYXZzbmFh1OoOgFD4VTUh9ZwgA=")
        #expect(storageServiceKey.deriveManifestKey(manifestVersion: 1).rawData.base64EncodedString() == "4Bm2DQtPJqmIJ6BvByPuWJmRTb4BS9fCXssU7nSr6a8=")
        #expect(storageServiceKey.deriveManifestKey(manifestVersion: 10).rawData.base64EncodedString() == "ccSiHKl53x+5DtWmVtYmJZkfqRXCKbCjQ02+MW8dYN4=")
        #expect(storageServiceKey.deriveLegacyRecordKey(itemIdentifier: StorageService.StorageIdentifier(
            data: Data(repeating: 1, count: 16),
            type: .account,
        )).rawData.base64EncodedString() == "3F9GA+ppdf4OV1GfD3ntUZyxAh4FPyUoHSpzRztwv1s=")
        #expect(storageServiceKey.deriveLegacyRecordKey(itemIdentifier: StorageService.StorageIdentifier(
            data: Data(repeating: 2, count: 16),
            type: .account,
        )).rawData.base64EncodedString() == "HZ+2K/BmhiF0JaWt9z/PrBAzo18kd3GoguRmg9U3F+0=")
        #expect(storageServiceKey.deriveLegacyRecordKey(itemIdentifier: StorageService.StorageIdentifier(
            data: Data(repeating: 1, count: 16),
            type: .contact,
        )).rawData.base64EncodedString() == "3F9GA+ppdf4OV1GfD3ntUZyxAh4FPyUoHSpzRztwv1s=")
    }
}
