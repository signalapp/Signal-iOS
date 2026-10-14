//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing
import XCTest

@testable import SignalServiceKit

struct UnreadReminderManagerTest {
    private typealias Category = UnreadReminderManager.Summary.Category

    private func body(
        unreadCount: Int,
        senderNames: [String] = [],
        mentions: Category = Category(),
        replies: Category = Category(),
    ) -> String {
        return UnreadReminderManager.notificationBody(for: UnreadReminderManager.Summary(
            messages: Category(count: unreadCount, senderNames: senderNames),
            mentions: mentions,
            replies: replies,
        ))
    }

    @Test
    func testMessagesFromSenders() {
        #expect(body(unreadCount: 1, senderNames: ["Lily"]) == "You have 1 unread message from Lily.")
        #expect(body(unreadCount: 5, senderNames: ["Lily", "Chrysanthemum"]) == "You have 5 unread messages from Lily and Chrysanthemum.")
        #expect(body(unreadCount: 5, senderNames: ["Lily", "Chrysanthemum", "Marigold"]) == "You have 5 unread messages from Lily and others.")
    }

    @Test
    func testWithoutNames() {
        #expect(body(unreadCount: 1) == "You have 1 unread message.")
        #expect(body(unreadCount: 2) == "You have 2 unread messages.")
    }

    @Test
    func testMentions() {
        #expect(
            body(unreadCount: 3, senderNames: ["Lily"], mentions: Category(count: 1, senderNames: ["Lily"]))
                == "You have 3 unread messages, including a mention of you by Lily.",
        )
        #expect(
            body(unreadCount: 9, senderNames: ["Lily", "Chrysanthemum"], mentions: Category(count: 2, senderNames: ["Lily", "Chrysanthemum"]))
                == "You have 9 unread messages, including 2 mentions of you by Lily and Chrysanthemum.",
        )
        #expect(
            body(unreadCount: 9, senderNames: ["Lily"], mentions: Category(count: 4, senderNames: ["Lily", "Chrysanthemum", "Marigold"]))
                == "You have 9 unread messages, including 4 mentions of you by Lily and others.",
        )
    }

    @Test
    func testReplies() {
        #expect(
            body(unreadCount: 3, senderNames: ["Lily"], replies: Category(count: 1, senderNames: ["Lily"]))
                == "You have 3 unread messages, including a reply from Lily.",
        )
        #expect(
            body(unreadCount: 9, senderNames: ["Lily"], replies: Category(count: 2, senderNames: ["Lily", "Chrysanthemum"]))
                == "You have 9 unread messages, including 2 replies from Lily and Chrysanthemum.",
        )
        #expect(
            body(unreadCount: 9, senderNames: ["Lily"], replies: Category(count: 5, senderNames: ["Lily", "Chrysanthemum", "Marigold"]))
                == "You have 9 unread messages, including 5 replies from Lily and others.",
        )
    }

    @Test
    func testMentionsAndReplies() {
        #expect(
            body(
                unreadCount: 9,
                senderNames: ["Lily", "Chrysanthemum"],
                mentions: Category(count: 1, senderNames: ["Lily"]),
                replies: Category(count: 3, senderNames: ["Chrysanthemum", "Marigold"]),
            ) == "You have 9 unread messages, including a mention of you by Lily and 3 replies from Chrysanthemum and Marigold.",
        )
    }
}

/// Exercises the unread scan against the database, which needs the full
/// environment, so this is an XCTest unlike the copy tests above.
class UnreadReminderSummaryTest: SSKBaseTest {
    private func insertUnreadMessages(_ count: Int, from authorAci: Aci, in thread: TSThread, tx: DBWriteTransaction) {
        for _ in 0..<count {
            let message = TSIncomingMessageBuilder.withDefaultValues(thread: thread, authorAci: authorAci).build()
            message.anyInsert(transaction: tx)
        }
    }

    private func summary(for thread: TSThread, tx: DBReadTransaction) -> UnreadReminderManager.Summary {
        let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
        return DependenciesBridge.shared.unreadReminderManager.fetchSummary(
            unreadCount: Int(finder.unreadCount(transaction: tx)),
            thread: thread,
            allowsNames: true,
            interactionFinder: finder,
            tx: tx,
        )
    }

    func testIncompleteScanKeepsOnlyTheCount() {
        write { tx in
            let thread = ContactThreadFactory().create(transaction: tx)
            let author = Aci.randomForTesting()

            // Inspecting exactly the limit is a complete scan.
            insertUnreadMessages(500, from: author, in: thread, tx: tx)
            XCTAssertEqual(summary(for: thread, tx: tx).messages.senderNames.count, 1)

            // One more, and a single name could misattribute it.
            insertUnreadMessages(1, from: author, in: thread, tx: tx)
            let incomplete = summary(for: thread, tx: tx)
            XCTAssertTrue(incomplete.messages.senderNames.isEmpty)
            XCTAssertEqual(UnreadReminderManager.notificationBody(for: incomplete), "You have 501 unread messages.")
        }
    }

    func testIncompleteScanKeepsAFullSetOfNames() {
        write { tx in
            // A group where mentions are summarized, so the scan can't stop
            // early once it has enough names.
            let members = (0..<4).map { _ in Aci.randomForTesting() }
            let thread = TSGroupThread.forUnitTest(
                groupId: Randomness.generateRandomBytes(32),
                groupMembers: members.map { SignalServiceAddress($0) },
            )
            thread.anyInsert(transaction: tx)
            XCTAssertTrue(thread.isGroupV2Thread)

            for member in members.dropLast() {
                insertUnreadMessages(1, from: member, in: thread, tx: tx)
            }
            insertUnreadMessages(498, from: members.last!, in: thread, tx: tx)

            let incomplete = summary(for: thread, tx: tx)
            XCTAssertEqual(incomplete.messages.senderNames.count, 3)
            XCTAssertEqual(incomplete.mentions.count, 0)
            XCTAssertTrue(UnreadReminderManager.notificationBody(for: incomplete).hasSuffix(" and others."))
        }
    }
}

class UnreadReminderPreferenceTest: SSKBaseTest {
    func testPerChatPreferenceFallsBackToGlobalSetting() {
        let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager
        let unreadReminderManager = DependenciesBridge.shared.unreadReminderManager
        write { tx in
            let thread = ContactThreadFactory().create(transaction: tx)
            XCTAssertFalse(notificationPreferencesManager.showUnreadReminders(thread: thread, tx: tx))

            unreadReminderManager.setGlobalShowUnreadReminders(true, updateStorageService: false, tx: tx)
            XCTAssertTrue(notificationPreferencesManager.showUnreadReminders(thread: thread, tx: tx))

            // A per-chat preference overrides the global setting.
            unreadReminderManager.setShowUnreadReminders(false, thread: thread, updateStorageService: false, tx: tx)
            XCTAssertFalse(notificationPreferencesManager.showUnreadReminders(thread: thread, tx: tx))

            // Clearing it restores the global setting.
            unreadReminderManager.setShowUnreadReminders(nil, thread: thread, updateStorageService: false, tx: tx)
            XCTAssertTrue(notificationPreferencesManager.showUnreadReminders(thread: thread, tx: tx))
        }
    }
}
