//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class MessageBackupDistributionListTest: MessageBackupIntegrationTestCase {
    typealias ListValidationBlock = ((TSPrivateStoryThread) -> Void)

    private var privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager { deps.privateStoryThreadDeletionManager }
    private var threadStore: ThreadStore { deps.threadStore }

    func testDistributionList() async throws {
        try await runTest(
            backupName: "story-distribution-list",
            dateProvider: {
                /// "Deleted distribution list" logic relies on the distance
                /// between timestamps in the Backup binary and the "current
                /// time". To keep this test stable over time, we need to
                /// hardcode the "current time"; the timestamp below is from the
                /// time this test was originally committed.
                return Date(millisecondsSince1970: 1717631700000)
            },
            // TODO: [Backups] Enable comparator.
            enableLibsignalComparator: false
        ) { sdsTx, tx in
            let deletedStories = privateStoryThreadDeletionManager.allDeletedIdentifiers(tx: tx)
            XCTAssertEqual(deletedStories.count, 2)

            let validationBlocks: [UUID: ListValidationBlock] = [
                UUID(uuidString: TSPrivateStoryThread.myStoryUniqueId)!: { thread in
                    XCTAssertTrue(thread.allowsReplies)
                },
                UUID(data: Data(base64Encoded: "me/ptJ9tRnyCWu/eg9uP7Q==")!)!: { thread in
                    XCTAssertEqual(thread.name, "Mandalorians")
                    XCTAssertTrue(thread.allowsReplies)
                    XCTAssertEqual(thread.storyViewMode, .blockList)
                    XCTAssertEqual(thread.addresses.count, 2)
                },
                UUID(data: Data(base64Encoded: "ZYoHlxwxS8aBGSQJ1tL0sA==")!)!: { thread in
                    XCTAssertEqual(thread.name, "Hutts")
                    XCTAssertFalse(thread.allowsReplies)
                    // check member list
                    XCTAssertEqual(thread.storyViewMode, .explicit)
                    XCTAssertEqual(thread.addresses.count, 1)
                }
            ]

            try threadStore.enumerateStoryThreads(tx: tx) { thread in
                do {
                    let validationBlock = try XCTUnwrap(validationBlocks[UUID(uuidString: thread.uniqueId)!])
                    validationBlock(thread)
                } catch {
                    XCTFail("Missing validation block")
                }

                return true
            }
        }
    }
}
