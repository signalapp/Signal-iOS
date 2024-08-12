//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupThreadMergeChatUpdateTest: MessageBackupIntegrationTestCase {
    func testThreadMergeChatUpdates() async throws {
        let expectedAci = Aci.parseFrom(aciString: "5F8C568D-0119-47BD-81AA-BB87C9B71995")!

        try await runTest(
            backupName: "thread-merge-chat-update-message",
            // TODO: [Backups] Enable comparator.
            enableLibsignalComparator: false
        ) { sdsTx, tx in
            let allInteractions = try deps.interactionStore.fetchAllInteractions(tx: tx)
            XCTAssertEqual(allInteractions.count, 1)

            guard
                let infoMessage = allInteractions.first! as? TSInfoMessage,
                let threadMergePhoneNumber = infoMessage.threadMergePhoneNumber
            else {
                XCTFail("Unexpectedly missing thread merge message and properties!")
                return
            }

            guard
                let mergedThread = deps.threadStore.fetchThreadForInteraction(infoMessage, tx: tx) as? TSContactThread,
                let mergedThreadAci = mergedThread.contactAddress.aci
            else {
                XCTFail("Unexpectedly missing merged thread and properties!")
                return
            }

            XCTAssertEqual(infoMessage.messageType, .threadMerge)
            XCTAssertEqual(threadMergePhoneNumber, "+17735550199")
            XCTAssertEqual(mergedThreadAci, expectedAci)
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
