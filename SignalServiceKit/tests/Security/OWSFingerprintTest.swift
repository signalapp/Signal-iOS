//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class OWSFingerprintTest: SSKBaseTestSwift {
    func testDisplayableTextInsertsSpaces() {
        let aliceStableAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+19995550101")
        let bobStableAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+18885550102")

        let aliceIdentityKey = Curve25519.generateKeyPair().publicKey
        let bobIdentityKey = Curve25519.generateKeyPair().publicKey

        let aliceToBobFingerprint = OWSFingerprint(
            myStableAddress: aliceStableAddress,
            myIdentityKey: aliceIdentityKey,
            theirStableAddress: bobStableAddress,
            theirIdentityKey: bobIdentityKey,
            theirName: "Bob",
            hashIterations: 2
        )
        let displayableText = aliceToBobFingerprint.displayableText

        let expectedGroupCount = 12
        let expectedGroupSize = 5

        let expectedResultLength = (expectedGroupCount * expectedGroupSize) + (expectedGroupCount - 1)
        XCTAssertEqual(displayableText.count, expectedResultLength)

        let components = displayableText.components(separatedBy: .whitespacesAndNewlines)
        XCTAssertEqual(components.count, expectedGroupCount)
        for component in components {
            XCTAssertEqual(component.count, expectedGroupSize)
            let match = component.range(of: #"^\d*$"#, options: .regularExpression)
            XCTAssertNotNil(match, "\(component) is not all digits")
        }
    }

    func testTextMatchesReciprocally() {
        let aliceStableAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+19995550101")
        let bobStableAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+18885550102")
        let charlieStableAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: "+17775550103")

        let aliceIdentityKey = Curve25519.generateKeyPair().publicKey
        let bobIdentityKey = Curve25519.generateKeyPair().publicKey
        let charlieIdentityKey = Curve25519.generateKeyPair().publicKey

        let aliceToBobFingerprint = OWSFingerprint(
            myStableAddress: aliceStableAddress,
            myIdentityKey: aliceIdentityKey,
            theirStableAddress: bobStableAddress,
            theirIdentityKey: bobIdentityKey,
            theirName: "Bob",
            hashIterations: 2
        )
        let bobToAliceFingerprint = OWSFingerprint(
            myStableAddress: bobStableAddress,
            myIdentityKey: bobIdentityKey,
            theirStableAddress: aliceStableAddress,
            theirIdentityKey: aliceIdentityKey,
            theirName: "Alice",
            hashIterations: 2
        )
        XCTAssertEqual(
            aliceToBobFingerprint.displayableText,
            bobToAliceFingerprint.displayableText
        )

        let charlieToAliceFingerprint = OWSFingerprint(
            myStableAddress: charlieStableAddress,
            myIdentityKey: charlieIdentityKey,
            theirStableAddress: aliceStableAddress,
            theirIdentityKey: aliceIdentityKey,
            theirName: "Alice",
            hashIterations: 2
        )
        XCTAssertNotEqual(
            aliceToBobFingerprint.displayableText,
            charlieToAliceFingerprint.displayableText
        )
    }
}
