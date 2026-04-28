//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing
@testable import SignalServiceKit

struct OWSFingerprintTest {
    private let aliceAci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000a1")
    private let bobAci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000b1")

    private let aliceIdentity = IdentityKey(
        publicKey: try! PrivateKey([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 64]).publicKey,
    )
    private let bobIdentity = IdentityKey(
        publicKey: try! PrivateKey([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 64]).publicKey,
    )

    @Test
    func testDisplayableText() {
        let aliceToBobFingerprint = OWSFingerprint(
            myAci: aliceAci,
            theirAci: bobAci,
            myAciIdentityKey: aliceIdentity,
            theirAciIdentityKey: bobIdentity,
            hashIterations: 2,
        )
        let displayableText = aliceToBobFingerprint.displayableText

        #expect(displayableText == "79869 05861 85368 01620\n29524 19262 97840 44452\n97466 75030 05834 47853")
    }

    @Test
    func testTextMatchesReciprocally() throws {
        let charlieAci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000c1")
        let charlieKey = try PrivateKey([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 64])
        let charlieIdentity = IdentityKey(publicKey: charlieKey.publicKey)

        let aliceToBobFingerprint = OWSFingerprint(
            myAci: aliceAci,
            theirAci: bobAci,
            myAciIdentityKey: aliceIdentity,
            theirAciIdentityKey: bobIdentity,
            hashIterations: 2,
        )
        let bobToAliceFingerprint = OWSFingerprint(
            myAci: bobAci,
            theirAci: aliceAci,
            myAciIdentityKey: bobIdentity,
            theirAciIdentityKey: aliceIdentity,
            hashIterations: 2,
        )
        #expect(aliceToBobFingerprint.displayableText == bobToAliceFingerprint.displayableText)

        let charlieToAliceFingerprint = OWSFingerprint(
            myAci: charlieAci,
            theirAci: aliceAci,
            myAciIdentityKey: charlieIdentity,
            theirAciIdentityKey: aliceIdentity,
            hashIterations: 2,
        )
        #expect(aliceToBobFingerprint.displayableText != charlieToAliceFingerprint.displayableText)
    }

    @Test
    func testCombinedFingerprints() throws {
        let bobCombinedFingerprints = try Textsecure_CombinedFingerprints(
            serializedBytes: Data(base64Encoded: "CAISIgogh2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0IU=")!,
        )
        let aliceToBobFingerprint = OWSFingerprint(
            myAci: aliceAci,
            theirAci: bobAci,
            myAciIdentityKey: aliceIdentity,
            theirAciIdentityKey: bobIdentity,
            hashIterations: 2,
        )
        try aliceToBobFingerprint.checkAgainst(combinedFingerprints: bobCombinedFingerprints)
    }

    @Test(arguments: [
        (OWSFingerprint.MatchError.weHaveOldVersion, "CAMSIgogh2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0IU="),
        (OWSFingerprint.MatchError.theyHaveOldVersion, "CAESIgogh2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0IU="),
        (OWSFingerprint.MatchError.weHaveWrongKeyForThem, "CAISIgogi2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0IU="),
        (OWSFingerprint.MatchError.theyHaveWrongKeyForUs, "CAISIgogh2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0JU="),
    ])
    func testCombinedFingerprintsFailures(testCase: (matchError: OWSFingerprint.MatchError, bobEncodedFingerprints: String)) {
        let bobCombinedFingerprints = try! Textsecure_CombinedFingerprints(
            serializedBytes: Data(base64Encoded: testCase.bobEncodedFingerprints)!,
        )
        let aliceToBobFingerprint = OWSFingerprint(
            myAci: aliceAci,
            theirAci: bobAci,
            myAciIdentityKey: aliceIdentity,
            theirAciIdentityKey: bobIdentity,
            hashIterations: 2,
        )
        #expect(throws: testCase.matchError) {
            try aliceToBobFingerprint.checkAgainst(combinedFingerprints: bobCombinedFingerprints)
        }
    }
}
