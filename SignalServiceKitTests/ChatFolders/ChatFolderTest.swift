//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import SignalServiceKit

struct ChatFolderTest {
    private let inMemoryDB = InMemoryDB()

    private func folder(name: String) -> ChatFolder {
        let record = inMemoryDB.write { tx in
            ChatFolderStore().insertCustomFolderRecord(
                chatFolderId: UUID(),
                name: name,
                position: 0,
                showOnlyUnread: false,
                showMutedChats: true,
                includeAllIndividualChats: false,
                includeAllGroupChats: false,
                deletedAtTimestampMs: 0,
                tx: tx,
            )
        }
        return ChatFolder(record: record, includedThreadRowIds: [], excludedThreadRowIds: [])
    }

    @Test
    func testDisplayNameIsClampedToTheMaxLength() {
        let name = String(repeating: "a", count: 40)
        #expect(folder(name: name).displayName == String(repeating: "a", count: ChatFolder.maxNameLength))
    }

    @Test
    func testDisplayNameCountsCharactersInsteadOfScalars() {
        let name = String(repeating: "👩‍👩‍👧", count: 40)
        #expect(folder(name: name).displayName == String(repeating: "👩‍👩‍👧", count: ChatFolder.maxNameLength))
    }

    @Test
    func testDisplayNameTrimsWhitespace() {
        #expect(folder(name: "  Work \n").displayName == "Work")
    }

    @Test
    func testBlankNameShowsAFallback() {
        let displayName = folder(name: " \n ").displayName
        #expect(!displayName.isEmpty)
        #expect(displayName == folder(name: "").displayName)
    }
}
