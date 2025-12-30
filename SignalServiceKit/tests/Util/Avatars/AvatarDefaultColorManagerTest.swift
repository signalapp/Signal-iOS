//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing
@testable import SignalServiceKit

struct AvatarDefaultColorManagerTest {
    private let avatarDefaultColorManager = AvatarDefaultColorManager()
    private let db = InMemoryDB()

    @Test
    func testDerivation() {
        struct TestCase {
            let defaultAvatarColorUseCase: AvatarDefaultColorManager.UseCase
            let expectedDefaultColor: AvatarTheme
        }

        let testCases = [
            TestCase(
                defaultAvatarColorUseCase: .contactWithoutRecipient(address: .isolatedForTesting(
                    serviceId: Aci.constantForTesting("a025bf78-653e-44e0-beb9-deb14ba32487"),
                )),
                expectedDefaultColor: .A140,
            ),
            TestCase(
                defaultAvatarColorUseCase: .contactWithoutRecipient(address: .isolatedForTesting(
                    serviceId: Pni.constantForTesting("PNI:11a175e3-fe31-4eda-87da-e0bf2a2e250b"),
                )),
                expectedDefaultColor: .A200,
            ),
            TestCase(
                defaultAvatarColorUseCase: .contactWithoutRecipient(address: .isolatedForTesting(
                    phoneNumber: "+12135550124",
                )),
                expectedDefaultColor: .A150,
            ),
            TestCase(
                defaultAvatarColorUseCase: .group(groupId: Data(
                    base64Encoded: "BwJRIdomqOSOckHjnJsknNCibCZKJFt+RxLIpa9CWJ4=",
                )!),
                expectedDefaultColor: .A130,
            ),
        ]

        for testCase in testCases {
            let derivedColor = AvatarDefaultColorManager.deriveDefaultColor(
                useCase: testCase.defaultAvatarColorUseCase,
            )

            #expect(derivedColor == testCase.expectedDefaultColor)
        }
    }

    @Test
    func testPersistedTakesPreference() {
        let groupId = Data(base64EncodedWithoutPadding: "BwJRIdomqOSOckHjnJsknNCibCZKJFt+RxLIpa9CWJ4")!
        let useCase: AvatarDefaultColorManager.UseCase = .group(groupId: groupId)

        #expect(AvatarDefaultColorManager.deriveDefaultColor(useCase: useCase) == .A130)

        db.write { tx in
            try! avatarDefaultColorManager.persistDefaultColor(.A200, groupId: groupId, tx: tx)
        }

        let defaultColor = db.read { tx in
            avatarDefaultColorManager.defaultColor(
                useCase: .group(groupId: groupId),
                tx: tx,
            )
        }

        #expect(defaultColor == .A200)
    }
}
