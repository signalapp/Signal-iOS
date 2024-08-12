//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupExpirationTimerChatUpdateTest: MessageBackupIntegrationTestCase {
    func testExpirationTimerChatUpdates() async throws {
        let contactAci = Aci.constantForTesting("5F8C568D-0119-47BD-81AA-BB87C9B71995")

        try await runTest(
            backupName: "expiration-timer-chat-update-message",
            // TODO: [Backups] Enable comparator.
            enableLibsignalComparator: false
        ) { sdsTx, tx in
            let fetchedContactThreads = deps.threadStore.fetchContactThreads(serviceId: contactAci, tx: tx)
            XCTAssertEqual(fetchedContactThreads.count, 1)
            let expectedContactThread = fetchedContactThreads.first!

            struct ExpectedExpirationTimerUpdate {
                let authorIsLocalUser: Bool
                let expiresInSeconds: UInt32
                var isEnabled: Bool { expiresInSeconds > 0 }
            }

            var expectedUpdates: [ExpectedExpirationTimerUpdate] = [
                .init(authorIsLocalUser: false, expiresInSeconds: 0),
                .init(authorIsLocalUser: true, expiresInSeconds: 9001),
            ]

            try deps.interactionStore.enumerateAllInteractions(tx: tx) { interaction -> Bool in
                XCTAssertEqual(interaction.uniqueThreadId, expectedContactThread.uniqueId)

                guard let dmUpdateInfoMessage = interaction as? OWSDisappearingConfigurationUpdateInfoMessage else {
                    XCTFail("Unexpected interaction type: \(type(of: interaction))")
                    return false
                }

                guard let expectedUpdate = expectedUpdates.popFirst() else {
                    XCTFail("Unexpectedly missing expected timer change!")
                    return false
                }

                XCTAssertEqual(dmUpdateInfoMessage.configurationDurationSeconds, expectedUpdate.expiresInSeconds)
                XCTAssertEqual(dmUpdateInfoMessage.configurationIsEnabled, expectedUpdate.isEnabled)
                if expectedUpdate.authorIsLocalUser {
                    XCTAssertNil(dmUpdateInfoMessage.createdByRemoteName)
                } else {
                    XCTAssertNotNil(dmUpdateInfoMessage.createdByRemoteName)
                }

                return true
            }
        }
    }
}
