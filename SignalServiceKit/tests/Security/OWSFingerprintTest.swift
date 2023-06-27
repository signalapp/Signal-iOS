//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class OWSFingerprintTest: XCTestCase {

    func testDisplayableTextInsertsSpaces() {
        let aliceE164 = E164("+19995550101")!
        let bobE164 = E164("+18885550102")!

        let aliceIdentityKey = Curve25519.generateKeyPair().publicKey
        let bobIdentityKey = Curve25519.generateKeyPair().publicKey

        let aliceToBobFingerprint = OWSFingerprint(
            source: .e164(myE164: aliceE164, theirE164: bobE164),
            myIdentityKey: aliceIdentityKey,
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
        let aliceE164 = E164("+19995550101")!
        let bobE164 = E164("+18885550102")!
        let charlieE164 = E164("+17775550103")!

        let aliceIdentityKey = Curve25519.generateKeyPair().publicKey
        let bobIdentityKey = Curve25519.generateKeyPair().publicKey
        let charlieIdentityKey = Curve25519.generateKeyPair().publicKey

        let aliceToBobFingerprint = OWSFingerprint(
            source: .e164(myE164: aliceE164, theirE164: bobE164),
            myIdentityKey: aliceIdentityKey,
            theirIdentityKey: bobIdentityKey,
            theirName: "Bob",
            hashIterations: 2
        )
        let bobToAliceFingerprint = OWSFingerprint(
            source: .e164(myE164: bobE164, theirE164: aliceE164),
            myIdentityKey: bobIdentityKey,
            theirIdentityKey: aliceIdentityKey,
            theirName: "Alice",
            hashIterations: 2
        )
        XCTAssertEqual(
            aliceToBobFingerprint.displayableText,
            bobToAliceFingerprint.displayableText
        )

        let charlieToAliceFingerprint = OWSFingerprint(
            source: .e164(myE164: charlieE164, theirE164: aliceE164),
            myIdentityKey: charlieIdentityKey,
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
