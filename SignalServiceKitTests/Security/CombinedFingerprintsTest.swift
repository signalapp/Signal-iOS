//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing
@testable import SignalServiceKit

struct CombinedFingerprintsTest {
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
        let aliceToBobFingerprint = CombinedFingerprints(
            local: .derive(forAci: aliceAci, identityKey: aliceIdentity, iterations: 2),
            remote: .derive(forAci: bobAci, identityKey: bobIdentity, iterations: 2),
        )
        let displayableText = aliceToBobFingerprint.displayableText()

        #expect(displayableText == "79869 05861 85368 01620\n29524 19262 97840 44452\n97466 75030 05834 47853")
    }

    @Test
    func testTextMatchesReciprocally() throws {
        let charlieAci = Aci.constantForTesting("00000000-0000-4000-8000-0000000000c1")
        let charlieKey = try PrivateKey([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 64])
        let charlieIdentity = IdentityKey(publicKey: charlieKey.publicKey)

        let aliceFingerprint = Fingerprint.derive(forAci: aliceAci, identityKey: aliceIdentity, iterations: 2)
        let bobFingerprint = Fingerprint.derive(forAci: bobAci, identityKey: bobIdentity, iterations: 2)
        let charlieFingerprint = Fingerprint.derive(forAci: charlieAci, identityKey: charlieIdentity, iterations: 2)

        let aliceToBobFingerprint = CombinedFingerprints(local: aliceFingerprint, remote: bobFingerprint)
        let bobToAliceFingerprint = CombinedFingerprints(local: bobFingerprint, remote: aliceFingerprint)
        #expect(aliceToBobFingerprint.displayableText() == bobToAliceFingerprint.displayableText())

        let charlieToAliceFingerprint = CombinedFingerprints(local: charlieFingerprint, remote: aliceFingerprint)
        #expect(aliceToBobFingerprint.displayableText() != charlieToAliceFingerprint.displayableText())
    }

    @Test
    func testCombinedFingerprints() throws {
        let bobCombinedFingerprints = try Textsecure_CombinedFingerprints(
            serializedBytes: Data(base64Encoded: "CAISIgogh2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0IU=")!,
        )
        let aliceToBobFingerprint = CombinedFingerprints(
            local: .derive(forAci: aliceAci, identityKey: aliceIdentity, iterations: 2),
            remote: .derive(forAci: bobAci, identityKey: bobIdentity, iterations: 2),
        )
        try aliceToBobFingerprint.checkAgainst(combinedFingerprints: bobCombinedFingerprints)
    }

    @Test(arguments: [
        (CombinedFingerprints.MatchError.weHaveOldVersion, "CAMSIgogh2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0IU="),
        (CombinedFingerprints.MatchError.theyHaveOldVersion, "CAESIgogh2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0IU="),
        (CombinedFingerprints.MatchError.weHaveWrongKeyForThem, "CAISIgogi2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0IU="),
        (CombinedFingerprints.MatchError.theyHaveWrongKeyForUs, "CAISIgogh2isJ/CLN4n95KkusJUazEq6p9YOBrWV6kvVk02NQSgaIgog828QHN1CX/GHRdrB7LJYTr6zxXQqYfv4dKqE57n+0JU="),
    ])
    func testCombinedFingerprintsFailures(testCase: (matchError: CombinedFingerprints.MatchError, bobEncodedFingerprints: String)) {
        let bobCombinedFingerprints = try! Textsecure_CombinedFingerprints(
            serializedBytes: Data(base64Encoded: testCase.bobEncodedFingerprints)!,
        )
        let aliceToBobFingerprint = CombinedFingerprints(
            local: .derive(forAci: aliceAci, identityKey: aliceIdentity, iterations: 2),
            remote: .derive(forAci: bobAci, identityKey: bobIdentity, iterations: 2),
        )
        #expect(throws: testCase.matchError) {
            try aliceToBobFingerprint.checkAgainst(combinedFingerprints: bobCombinedFingerprints)
        }
    }
}
