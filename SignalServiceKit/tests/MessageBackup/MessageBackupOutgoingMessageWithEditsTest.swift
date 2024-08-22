//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupOutgoingMessageWithEditsTest: MessageBackupIntegrationTestCase {
    private struct FailTestError: Error {
        init(_ message: String) {
            XCTFail(message)
        }
    }

    func testOutgoingMessageWithEdits() async throws {
        let hanAci = Aci.constantForTesting("5F8C568D-0119-47BD-81AA-BB87C9B71995")

        try await runTest(
            backupName: "outgoing-message-with-edits",
            enableLibsignalComparator: false
        ) { sdsTx, tx in
            let allInteractions = try deps.interactionStore.fetchAllInteractions(tx: tx)
            /// The message, and two previous revisions.
            XCTAssertEqual(allInteractions.count, 3)

            /// The most recent revision will be the oldest message, or the last
            /// one fetched.
            let mostRecentRevision = allInteractions[2] as! TSOutgoingMessage
            /// Ordered newest -> oldest.
            let editHistory = try deps.editMessageStore.findEditHistory(for: mostRecentRevision, tx: tx)
            XCTAssertEqual(editHistory.count, 2)
            /// Original revision is the oldest in edit history...
            let originalRevision: TSOutgoingMessage = editHistory[1].message!
            /// ...and intermediate revision is the newest.
            let middleRevision: TSOutgoingMessage = editHistory[0].message!

            /// Confirm all the messages are from Han and in the expected group.
            XCTAssertTrue([mostRecentRevision, middleRevision, originalRevision].allSatisfy { outgoingMessage -> Bool in
                guard let contactThread = deps.threadStore.fetchThread(
                    uniqueId: outgoingMessage.uniqueThreadId,
                    tx: tx
                ) as? TSContactThread else {
                    XCTFail("Missing contact thread for outgoing message!")
                    return false
                }

                return contactThread.contactUUID == hanAci.serviceIdUppercaseString
            })

            func singleRecipientState(_ outgoingMessage: TSOutgoingMessage) throws -> TSOutgoingMessageRecipientState {
                guard
                    let recipientAddressStates = outgoingMessage.recipientAddressStates,
                    recipientAddressStates.count == 1,
                    let single = recipientAddressStates.first
                else { throw FailTestError("Missing single recipient state!") }

                return single.value
            }

            /// Verify the original message contents are correct...
            XCTAssertEqual(originalRevision.body, "Original message")
            XCTAssertEqual(originalRevision.timestamp, 1000)
            XCTAssertNil(try singleRecipientState(originalRevision).errorCode)
            XCTAssertEqual(try singleRecipientState(originalRevision).state, .sent)
            XCTAssertEqual(try singleRecipientState(originalRevision).readTimestamp?.uint64Value, 1001)
            XCTAssertEqual(originalRevision.editState, .pastRevision)

            /// ...and that we got the intermediate revision...
            XCTAssertEqual(middleRevision.body, "First revision")
            XCTAssertEqual(middleRevision.timestamp, 2000)
            XCTAssertNil(try singleRecipientState(middleRevision).errorCode)
            XCTAssertEqual(try singleRecipientState(middleRevision).state, .sent)
            XCTAssertEqual(try singleRecipientState(middleRevision).deliveryTimestamp?.uint64Value, 2001)
            XCTAssertEqual(middleRevision.editState, .pastRevision)

            /// ...and the final revision...
            XCTAssertEqual(mostRecentRevision.body, "Latest revision")
            XCTAssertEqual(mostRecentRevision.timestamp, 3000)
            XCTAssertNil(try singleRecipientState(mostRecentRevision).errorCode)
            XCTAssertEqual(try singleRecipientState(mostRecentRevision).state, .sent)
            XCTAssertEqual(mostRecentRevision.editState, .latestRevisionRead)

            /// ...and its downstream reactions.
            let reactions = deps.reactionStore
                .allReactions(messageId: mostRecentRevision.uniqueId, tx: tx)
                .sorted(by: { $0.sortOrder < $1.sortOrder })
            XCTAssertEqual(reactions.map { $0.emoji }, ["👀", "🥂"])
            XCTAssertEqual(reactions.map { $0.sentAtTimestamp }, [101, 102])
            XCTAssertEqual(reactions.map { $0.reactorAci }, [localIdentifiers.aci, hanAci])
        }
    }
}

// MARK: -

private extension InteractionStore {
    /// Fetches all interactions, from newest -> oldest.
    func fetchAllInteractions(tx: any DBReadTransaction) throws -> [TSInteraction] {
        var results = [TSInteraction]()
        try enumerateAllInteractions(tx: tx) { interaction in
            results.append(interaction)
            return true
        }
        return results.sorted { lhs, rhs in
            return lhs.sqliteRowId! > rhs.sqliteRowId!
        }
    }
}
