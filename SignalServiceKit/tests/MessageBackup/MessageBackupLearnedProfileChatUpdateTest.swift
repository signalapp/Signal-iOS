//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupLearnedProfileChatUpdateTest: MessageBackupIntegrationTestCase {
    func testLearnedProfileChatUpdates() async throws {
        let expectedAci = Aci.parseFrom(aciString: "5F8C568D-0119-47BD-81AA-BB87C9B71995")!

        try await runTest(
            backupName: "learned-profile-chat-update-message",
            // TODO: [Backups] Enable comparator.
            enableLibsignalComparator: false
        ) { sdsTx, tx in
            let allInteractions = try deps.interactionStore.fetchAllInteractions(tx: tx)
            XCTAssertEqual(allInteractions.count, 2)

            let expectedDisplayNames: [TSInfoMessage.DisplayNameBeforeLearningProfileName] = [
                .username("boba_fett.99"),
                .phoneNumber("+17735550199"),
            ]

            for (idx, interaction) in allInteractions.enumerated() {
                guard
                    let contactThread = deps.threadStore.fetchThreadForInteraction(interaction, tx: tx) as? TSContactThread,
                    let contactAci = Aci.parseFrom(aciString: contactThread.contactUUID),
                    let infoMessage = interaction as? TSInfoMessage,
                    let displayNameBeforeLearningProfileName = infoMessage.displayNameBeforeLearningProfileName
                else {
                    XCTFail("Unexpectedly missing expected info message and properties!")
                    return
                }

                XCTAssertEqual(contactAci, expectedAci)
                XCTAssertEqual(infoMessage.messageType, .learnedProfileName)
                XCTAssertEqual(displayNameBeforeLearningProfileName, expectedDisplayNames[idx])
            }
        }
    }
}

private extension InteractionStore {
    func fetchAllInteractions(tx: any DBReadTransaction) throws -> [TSInteraction] {
        var results = [TSInteraction]()
        try enumerateAllInteractions(tx: tx) { interaction in
            results.append(interaction)
            return true
        }
        return results
    }
}
