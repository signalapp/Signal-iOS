//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class OWSDeviceNamesTest: XCTestCase {
    func testNotEncrypted() {
        let identityKeyPair = IdentityKeyPair.generate()

        let plaintext = "alice"

        do {
            _ = try OWSDeviceNames.decryptDeviceName(base64String: plaintext, identityKeyPair: identityKeyPair)
            XCTFail("Unexpectedly did not throw error.")
        } catch OWSDeviceNameError.invalidInput {
            // Expected error.
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testStable() throws {
        let identityPrivateKey = try PrivateKey(Array(repeating: 0, count: 31) + [0x41])
        let identityKeyPair = IdentityKeyPair(publicKey: identityPrivateKey.publicKey, privateKey: identityPrivateKey)

        let encryptedDeviceName = try XCTUnwrap(Data(
            base64Encoded: "CiEFrYxIwmdlrqetxTYolgXBq+qVBQCT29IYyWq9JIGgNWUSEFNO1AI2/J8BQ+9Re91Y5OcaBsNYrahasg=="
        ))

        let deviceName = try OWSDeviceNames.decryptDeviceName(protoData: encryptedDeviceName, identityKeyPair: identityKeyPair)
        XCTAssertEqual(deviceName, "Abc123")
    }

    func testEncrypted() {
        let identityKeyPair = IdentityKeyPair.generate()

        let encrypted = try! OWSDeviceNames.encryptDeviceName(plaintext: "alice", identityKeyPair: identityKeyPair)
        let payload = encrypted.base64EncodedString()

        let decrypted = try! OWSDeviceNames.decryptDeviceName(base64String: payload, identityKeyPair: identityKeyPair)
        XCTAssertEqual("alice", decrypted)
    }

    func testBadlyEncrypted() {
        let identityKeyPair = IdentityKeyPair.generate()

        let encrypted = try! OWSDeviceNames.encryptDeviceName(plaintext: "alice", identityKeyPair: identityKeyPair)
        let payload = encrypted.base64EncodedString()

        let otherKeyPair = IdentityKeyPair.generate()
        do {
            _ = try OWSDeviceNames.decryptDeviceName(base64String: payload, identityKeyPair: otherKeyPair)
            XCTFail("Unexpectedly did not throw error.")
        } catch OWSDeviceNameError.cryptError {
            // Expected error.
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}
