//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupProfileChangeChatUpdateTest: MessageBackupIntegrationTestCase {
    func testProfileChange() async throws {
        let expectedAci = Aci.parseFrom(aciString: "5F8C568D-0119-47BD-81AA-BB87C9B71995")!

        try await runTest(
            backupName: "profile-change-chat-update-message",
            // TODO: [Backups] Enable comparator.
            enableLibsignalComparator: false
        ) { sdsTx, tx in
            let allInteractions = try deps.interactionStore.fetchAllInteractions(tx: tx)
            XCTAssertEqual(allInteractions.count, 1)

            guard
                let profileChangeInfoMessage = allInteractions.first as? TSInfoMessage,
                let profileChangeAddress = profileChangeInfoMessage.profileChangeAddress,
                let oldName = profileChangeInfoMessage.profileChangesOldFullName,
                let newName = profileChangeInfoMessage.profileChangesNewFullName
            else {
                XCTFail("Missing profile change properties!")
                return
            }

            XCTAssertEqual(profileChangeInfoMessage.messageType, .profileUpdate)
            XCTAssertEqual(profileChangeAddress.aci, expectedAci)
            XCTAssertEqual(oldName, "Snoop Dogg")
            XCTAssertEqual(newName, "Snoop Lion")
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
