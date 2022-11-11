//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import Curve25519Kit

@testable import SignalServiceKit

class DeviceNamesTest: SSKBaseTestSwift {
    func testNotEncrypted() {
        let identityKeyPair = Curve25519.generateKeyPair()

        let plaintext = "alice"

        do {
            _ = try DeviceNames.decryptDeviceName(base64String: plaintext,
                                                  identityKeyPair: identityKeyPair)
            XCTFail("Unexpectedly did not throw error.")
        } catch DeviceNameError.invalidInput {
            // Expected error.
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testEncrypted() {
        let identityKeyPair = Curve25519.generateKeyPair()

        let encrypted = try! DeviceNames.encryptDeviceName(plaintext: "alice",
                                                           identityKeyPair: identityKeyPair)
        let payload = encrypted.base64EncodedString()

        let decrypted = try! DeviceNames.decryptDeviceName(base64String: payload,
                                                           identityKeyPair: identityKeyPair)
        XCTAssertEqual("alice", decrypted)
    }

    func testBadlyEncrypted() {
        let identityKeyPair = Curve25519.generateKeyPair()

        let encrypted = try! DeviceNames.encryptDeviceName(plaintext: "alice",
                                                           identityKeyPair: identityKeyPair)
        let payload = encrypted.base64EncodedString()

        let otherKeyPair = Curve25519.generateKeyPair()
        do {
            _ = try DeviceNames.decryptDeviceName(base64String: payload,
                                                  identityKeyPair: otherKeyPair)
            XCTFail("Unexpectedly did not throw error.")
        } catch DeviceNameError.cryptError {
            // Expected error.
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}
