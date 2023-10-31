//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class DeviceNamesTest: XCTestCase {
    func testNotEncrypted() {
        let identityKeyPair = IdentityKeyPair.generate()

        let plaintext = "alice"

        do {
            _ = try DeviceNames.decryptDeviceName(base64String: plaintext, identityKeyPair: identityKeyPair)
            XCTFail("Unexpectedly did not throw error.")
        } catch DeviceNameError.invalidInput {
            // Expected error.
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testStable() throws {
        let identityPrivateKey = try PrivateKey(Array(repeating: 0, count: 31) + [0x41])
        let identityKeyPair = IdentityKeyPair(publicKey: identityPrivateKey.publicKey, privateKey: identityPrivateKey)

        let otherPrivateKey = try PrivateKey(Array(repeating: 0, count: 31) + [0x42])
        let otherKeyPair = IdentityKeyPair(publicKey: otherPrivateKey.publicKey, privateKey: otherPrivateKey)

        let encryptedDeviceName = try XCTUnwrap(Data(
            base64Encoded: "CiEFrYxIwmdlrqetxTYolgXBq+qVBQCT29IYyWq9JIGgNWUSEFNO1AI2/J8BQ+9Re91Y5OcaBsNYrahasg=="
        ))

        let deviceName = try DeviceNames.decryptDeviceName(protoData: encryptedDeviceName, identityKeyPair: identityKeyPair)
        XCTAssertEqual(deviceName, "Abc123")
    }

    func testEncrypted() {
        let identityKeyPair = IdentityKeyPair.generate()

        let encrypted = try! DeviceNames.encryptDeviceName(plaintext: "alice", identityKeyPair: identityKeyPair)
        let payload = encrypted.base64EncodedString()

        let decrypted = try! DeviceNames.decryptDeviceName(base64String: payload, identityKeyPair: identityKeyPair)
        XCTAssertEqual("alice", decrypted)
    }

    func testBadlyEncrypted() {
        let identityKeyPair = IdentityKeyPair.generate()

        let encrypted = try! DeviceNames.encryptDeviceName(plaintext: "alice", identityKeyPair: identityKeyPair)
        let payload = encrypted.base64EncodedString()

        let otherKeyPair = IdentityKeyPair.generate()
        do {
            _ = try DeviceNames.decryptDeviceName(base64String: payload, identityKeyPair: otherKeyPair)
            XCTFail("Unexpectedly did not throw error.")
        } catch DeviceNameError.cryptError {
            // Expected error.
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}
