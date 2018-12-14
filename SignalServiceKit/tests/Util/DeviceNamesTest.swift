//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import Curve25519Kit

@testable import SignalServiceKit

class DeviceNamesTest: SSKBaseTestSwift {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: 

    func testNotEncrypted() {

        let identityKeyPair = Curve25519.generateKeyPair()

        let plaintext = "alice"
        guard let plaintextData = plaintext.data(using: .utf8) else {
            XCTFail("Could not convert text to UTF-8.")
            return
        }

        do {
            _ = try DeviceNames.decryptDeviceName(input: plaintextData,
                                                      identityKeyPair: identityKeyPair)
            XCTFail("Unexpectedly did not throw error.")
        } catch {
            // Failure is expected.
        }
    }

    func testSimple() {

        let identityKeyPair = Curve25519.generateKeyPair()

        let plaintext = "alice"
        let encrypted: Data
        do {
            encrypted = try DeviceNames.encryptDeviceName(plaintext: plaintext,
                                                      identityKeyPair: identityKeyPair)
        } catch {
            XCTFail("Failed with error: \(error)")
            return
        }

        let decrypted: String
        do {
            decrypted = try DeviceNames.decryptDeviceName(input: encrypted,
                                                      identityKeyPair: identityKeyPair)
        } catch {
            XCTFail("Failed with error: \(error)")
            return
        }
        XCTAssertEqual(plaintext, decrypted)
    }
}
