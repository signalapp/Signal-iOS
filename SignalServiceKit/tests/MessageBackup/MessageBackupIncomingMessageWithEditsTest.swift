//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupIncomingMessageWithEditsTest: MessageBackupIntegrationTestCase {
    private var mentionPlaceholder: String { MessageBody.mentionPlaceholder }

    func testIncomingMessageWithEdits() async throws {
        let hanAci = Aci.constantForTesting("5F8C568D-0119-47BD-81AA-BB87C9B71995")
        let chewieAci = Aci.constantForTesting("0AE8C6C8-2707-4EA7-B224-7417227D3890")

        try await runTest(
            backupName: "incoming-message-with-edits",
            // TODO: [Backups] Enable comparator.
            enableLibsignalComparator: false
        ) { sdsTx, tx in
            let allGroupThreads = try deps.threadStore.fetchAllGroupThreads(tx: tx)
            XCTAssertEqual(allGroupThreads.count, 1)
            let groupThread = allGroupThreads.first!

            let allInteractions = try deps.interactionStore.fetchAllInteractions(tx: tx)
            /// The message, and two previous revisions.
            XCTAssertEqual(allInteractions.count, 3)

            /// The most recent revision will be the oldest message, or the last
            /// one fetched.
            let mostRecentRevision = allInteractions[2] as! TSIncomingMessage
            /// Ordered newest -> oldest.
            let editHistory = try deps.editMessageStore.findEditHistory(for: mostRecentRevision, tx: tx)
            XCTAssertEqual(editHistory.count, 2)
            /// Original revision is the oldest in edit history...
            let originalRevision: TSIncomingMessage = editHistory[1].message!
            /// ...and intermediate revision is the newest.
            let middleRevision: TSIncomingMessage = editHistory[0].message!

            /// Confirm all the messages are from Han and in the expected group.
            XCTAssertTrue([mostRecentRevision, middleRevision, originalRevision].allSatisfy { incomingMessage -> Bool in
                return
                    incomingMessage.uniqueThreadId == groupThread.uniqueId
                    && incomingMessage.authorUUID == hanAci.serviceIdUppercaseString
            })

            /// Verify the original message contents are correct...
            XCTAssertEqual(originalRevision.body, "Original message")
            XCTAssertEqual(originalRevision.timestamp, 1000)
            XCTAssertEqual(originalRevision.serverTimestamp, 1001)
            XCTAssertEqual(originalRevision.receivedAtTimestamp, 1002)
            XCTAssertEqual(originalRevision.editState, .pastRevision)
            XCTAssertTrue(originalRevision.wasRead)
            originalRevision.assertStyle(.italic, inRange: NSRange(location: 9, length: 7))

            /// ...and that we got the intermediate revision...
            XCTAssertEqual(middleRevision.body, "First revision: \(mentionPlaceholder)")
            XCTAssertEqual(middleRevision.timestamp, 2000)
            XCTAssertEqual(middleRevision.serverTimestamp, 2001)
            XCTAssertEqual(middleRevision.receivedAtTimestamp, 2002)
            XCTAssertTrue(middleRevision.wasRead)
            XCTAssertEqual(middleRevision.editState, .pastRevision)
            middleRevision.assertAciMention(chewieAci, atLocation: 16)

            /// ...and the final revision...
            XCTAssertEqual(mostRecentRevision.body, "Latest revision: \(mentionPlaceholder)")
            XCTAssertEqual(mostRecentRevision.timestamp, 3000)
            XCTAssertEqual(mostRecentRevision.serverTimestamp, 3001)
            XCTAssertEqual(mostRecentRevision.receivedAtTimestamp, 3002)
            XCTAssertEqual(mostRecentRevision.editState, .latestRevisionRead)
            XCTAssertTrue(mostRecentRevision.wasRead)
            mostRecentRevision.assertAciMention(chewieAci, atLocation: 17)
            mostRecentRevision.assertStyle(.italic, inRange: NSRange(location: 0, length: 6))

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

private extension TSIncomingMessage {
    func assertAciMention(_ aci: Aci, atLocation location: Int) {
        guard
            let mentions = bodyRanges?.mentions,
            mentions.count == 1,
            let singleMention = mentions.first
        else {
            XCTFail("Failed to extract single mention from body ranges!")
            return
        }

        XCTAssertEqual(singleMention.key, NSRange(location: location, length: 1))
        XCTAssertEqual(singleMention.value, aci)
    }

    func assertStyle(_ style: MessageBodyRanges.Style, inRange range: NSRange) {
        guard
            let styles = bodyRanges?.collapsedStyles,
            styles.count == 1,
            let firstStyle = styles.first
        else {
            XCTFail("Failed to extract single style entry from body ranges!")
            return
        }

        XCTAssertEqual(firstStyle.range, range)
        XCTAssertEqual(firstStyle.value.style, style)
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

private extension ThreadStore {
    func fetchAllGroupThreads(tx: any DBReadTransaction) throws -> [TSGroupThread] {
        var results = [TSGroupThread]()
        try enumerateGroupThreads(tx: tx) { groupThread in
            results.append(groupThread)
            return true
        }
        return results
    }
}
