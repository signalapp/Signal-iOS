//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import XCTest

final class OWSFingerprintTest: XCTestCase {

    func testDisplayableTextInsertsSpaces() {
        let aliceAci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
        let bobAci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000b1")

        let aliceIdentityKey = IdentityKeyPair.generate().identityKey
        let bobIdentityKey = IdentityKeyPair.generate().identityKey

        let aliceToBobFingerprint = OWSFingerprint(
            myAci: aliceAci,
            theirAci: bobAci,
            myAciIdentityKey: aliceIdentityKey,
            theirAciIdentityKey: bobIdentityKey,
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
        let aliceAci = Aci.randomForTesting()
        let bobAci = Aci.randomForTesting()
        let charlieAci = Aci.randomForTesting()

        let aliceIdentityKey = IdentityKeyPair.generate().identityKey
        let bobIdentityKey = IdentityKeyPair.generate().identityKey
        let charlieIdentityKey = IdentityKeyPair.generate().identityKey

        let aliceToBobFingerprint = OWSFingerprint(
            myAci: aliceAci,
            theirAci: bobAci,
            myAciIdentityKey: aliceIdentityKey,
            theirAciIdentityKey: bobIdentityKey,
            theirName: "Bob",
            hashIterations: 2
        )
        let bobToAliceFingerprint = OWSFingerprint(
            myAci: bobAci,
            theirAci: aliceAci,
            myAciIdentityKey: bobIdentityKey,
            theirAciIdentityKey: aliceIdentityKey,
            theirName: "Alice",
            hashIterations: 2
        )
        XCTAssertEqual(
            aliceToBobFingerprint.displayableText,
            bobToAliceFingerprint.displayableText
        )

        let charlieToAliceFingerprint = OWSFingerprint(
            myAci: charlieAci,
            theirAci: aliceAci,
            myAciIdentityKey: charlieIdentityKey,
            theirAciIdentityKey: aliceIdentityKey,
            theirName: "Alice",
            hashIterations: 2
        )
        XCTAssertNotEqual(
            aliceToBobFingerprint.displayableText,
            charlieToAliceFingerprint.displayableText
        )
    }
}
