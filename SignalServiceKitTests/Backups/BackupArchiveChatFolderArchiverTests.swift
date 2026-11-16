//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct BackupArchiveChatFolderArchiverTests {
    private let db = InMemoryDB()
    private let store = ChatFolderStore()
    private let archiver = BackupArchiveChatFolderArchiver(chatFolderStore: ChatFolderStore(), groupStore: GroupStore())

    @Test
    func testRestoresOrderFiltersAndMemberships() {
        db.write { tx in
            let originalAll = store.fetchOrInsertAllChatsRecord(tx: tx)
            let context = restoringContext(tx: tx)
            let recipients = context.recipientContext
            let contact = try! SignalRecipient.insertRecord(aci: Aci.randomForTesting(), tx: tx)
            recipients[.init(value: 1)] = .contact(.init(aci: contact.aci!))
            recipients.setRecipientDbRowId(contact.id, forBackupRecipientId: .init(value: 1))
            let local = try! SignalRecipient.insertRecord(aci: recipients.localIdentifiers.aci, tx: tx)
            recipients[.init(value: 2)] = .localAddress
            recipients.localSignalRecipientRowId = local.id
            let group = GroupRecord.insertRecord(
                groupId: Randomness.generateRandomBytes(32),
                threadId: nil,
                masterKey: nil,
                refreshedAt: Date(),
                tx: tx,
            )
            recipients[.init(value: 3)] = .group(.init(groupId: group.groupId))

            var custom = folder()
            custom.showOnlyUnread = true
            custom.showMutedChats = false
            custom.includeAllIndividualChats = true
            custom.includeAllGroupChats = true
            custom.includedRecipientIds = [1, 2, 3]
            custom.excludedRecipientIds = [2]
            expectSuccess(archiver.restore(custom, context: context))
            var all = folder(type: .all)
            all.name = ""
            expectSuccess(archiver.restore(all, context: context))

            let records = store.fetchDisplayableRecords(tx: tx)
            #expect(records.map(\.chatFolderId) == [UUID(data: custom.id)!, UUID(data: all.id)!])
            #expect(records.map(\.position) == [0, 1])
            #expect(records[1].id == originalAll.id)
            #expect(records[0].showOnlyUnread)
            #expect(!records[0].showMutedChats)
            #expect(records[0].includeAllIndividualChats)
            #expect(records[0].includeAllGroupChats)
            let memberships = store.fetchMemberships(folderRowId: records[0].id, tx: tx)
            #expect(Set(memberships.map(\.chat)) == [
                .contact(recipientRowId: contact.id),
                .contact(recipientRowId: local.id),
                .group(groupRowId: group.rowId),
            ])
            #expect(memberships.first { $0.chat == .contact(recipientRowId: local.id) }?.membershipType == .excluded)
        }
    }

    @Test
    func testRestoresOnlyAllChatsIdAndPosition() {
        db.write { tx in
            let original = store.fetchOrInsertAllChatsRecord(tx: tx)
            let context = restoringContext(tx: tx)
            context.nextPosition = 1
            var proto = folder(type: .all)
            proto.name = "Ignored name"
            proto.showOnlyUnread = true
            proto.showMutedChats = false
            proto.includeAllIndividualChats = false
            proto.includeAllGroupChats = false
            proto.includedRecipientIds = [1]
            proto.excludedRecipientIds = [2]

            expectSuccess(archiver.restore(proto, context: context))

            let restored = store.fetchRecordForAllChatsFolder(tx: tx)!
            #expect(restored.id == original.id)
            #expect(restored.position == 1)
            #expect(restored.name == original.name)
            #expect(restored.showOnlyUnread == original.showOnlyUnread)
            #expect(restored.showMutedChats == original.showMutedChats)
            #expect(restored.includeAllIndividualChats == original.includeAllIndividualChats)
            #expect(restored.includeAllGroupChats == original.includeAllGroupChats)
            #expect(restored.chatFolderId == UUID(data: proto.id)!)
            #expect(store.fetchMemberships(folderRowId: restored.id, tx: tx).isEmpty)
            #expect(context.nextPosition == 2)
            #expect(context.hasRestoredAllChats)
            #expect(context.restoredIds.contains(restored.chatFolderId))
        }
    }

    @Test
    func testRejectsInvalidAndDuplicateFolders() {
        db.write { tx in
            let context = restoringContext(tx: tx)
            var invalid = folder()
            invalid.id = Data([1])
            guard case .failure = archiver.restore(invalid, context: context) else {
                Issue.record("Expected invalid ID to fail")
                return
            }
            let all = folder(type: .all)
            expectSuccess(archiver.restore(all, context: context))
            for duplicate in [all, folder(type: .all), folder(id: UUID(data: all.id)!)] {
                guard case .failure = archiver.restore(duplicate, context: context) else {
                    Issue.record("Expected duplicate folder to fail")
                    continue
                }
            }
            #expect(store.fetchAllRecords(tx: tx).count == 1)
        }
    }

    @Test
    func testUnknownTypeRestoresAsCustomAndInvalidRecipientsAreDropped() {
        db.write { tx in
            let context = restoringContext(tx: tx)
            var proto = folder(type: .UNRECOGNIZED(42))
            context.recipientContext[.init(value: 2)] = .releaseNotesChannel
            proto.includedRecipientIds = [1, 2]
            guard case .partialRestore(let errors) = archiver.restore(proto, context: context) else {
                Issue.record("Expected invalid recipients to produce partial restore")
                return
            }
            #expect(errors.count == 2)
            let record = store.fetchRecord(chatFolderId: UUID(data: proto.id)!, tx: tx)!
            #expect(record.folderType == .custom)
            #expect(store.fetchMemberships(folderRowId: record.id, tx: tx).isEmpty)
        }
    }

    @Test
    func testArchivesLiveFoldersInOrderWithMappedRecipients() throws {
        try db.write { tx in
            let local = try SignalRecipient.insertRecord(aci: LocalIdentifiers.forUnitTests.aci, tx: tx)
            let context = BackupArchive.RecipientArchivingContext(
                localRecipientId: .init(value: 1),
                localSignalRecipientRowId: local.id,
                localIdentifiers: .forUnitTests,
                startDate: Date(),
                remoteConfig: RemoteConfig(clockSkew: 0, valueFlags: [:]),
                currentUploadEra: "",
                bencher: BackupArchive.ArchiveBencher(dateProviderMonotonic: { MonotonicDate() }, memorySampler: NoopMemorySampler()),
                includedContentFilter: .remoteBackup,
                perFrameAccumulator: .init(attachmentByteCounter: BackupArchiveAttachmentByteCounter(), localFileBackupAttachmentCollector: nil),
                tx: tx,
            )
            let stream = FrameStream()
            _ = store.fetchOrInsertAllChatsRecord(tx: tx)
            _ = try archiver.archiveChatFolders(stream: stream, context: context)
            #expect(stream.frames.isEmpty)

            let restoreContext = restoringContext(tx: tx)
            let custom = folder()
            expectSuccess(archiver.restore(custom, context: restoreContext))
            let deleted = folder()
            expectSuccess(archiver.restore(deleted, context: restoreContext))
            store.markDeleted(chatFolderId: UUID(data: deleted.id)!, deletedAtTimestampMs: 1, tx: tx)
            let record = store.fetchRecord(chatFolderId: UUID(data: custom.id)!, tx: tx)!
            store.setMembership(.included, chat: .contact(recipientRowId: local.id), folderRowId: record.id, tx: tx)
            let group = GroupRecord.insertRecord(groupId: Randomness.generateRandomBytes(32), threadId: nil, masterKey: nil, refreshedAt: Date(), tx: tx)
            let omitted = try SignalRecipient.insertRecord(aci: Aci.randomForTesting(), tx: tx)
            store.setMembership(.included, chat: .contact(recipientRowId: omitted.id), folderRowId: record.id, tx: tx)
            let groupRecipientId = context.assignRecipientId(to: .group(.init(groupId: group.groupId)))
            store.setMembership(.excluded, chat: .group(groupRowId: group.rowId), folderRowId: record.id, tx: tx)

            // Stored All chats settings and membership must not affect its backup representation.
            var allChats = store.fetchOrInsertAllChatsRecord(tx: tx)
            allChats.name = "Ignored name"
            allChats.showOnlyUnread = true
            allChats.showMutedChats = false
            allChats.includeAllIndividualChats = false
            allChats.includeAllGroupChats = false
            store.update(allChats, tx: tx)
            store.setMembership(.included, chat: .contact(recipientRowId: local.id), folderRowId: allChats.id, tx: tx)
            store.setMembership(.excluded, chat: .group(groupRowId: group.rowId), folderRowId: allChats.id, tx: tx)

            _ = try archiver.archiveChatFolders(stream: stream, context: context)
            #expect(stream.frames.count == 2)
            let archivedAll = stream.frames.first { $0.chatFolder.folderType == .all }!.chatFolder
            #expect(archivedAll == folder(id: allChats.chatFolderId, type: .all))
            let archived = stream.frames.first { $0.chatFolder.id == custom.id }!.chatFolder
            #expect(archived.name == custom.name)
            #expect(archived.includedRecipientIds == [1])
            #expect(archived.excludedRecipientIds == [groupRecipientId.value])
            #expect(stream.frames.map { $0.chatFolder.id } == store.fetchDisplayableRecords(tx: tx).map { $0.chatFolderId.data })
        }
    }

    private func restoringContext(tx: DBWriteTransaction) -> BackupArchiveChatFolderArchiver.RestoringContext {
        return .init(recipientContext: BackupArchive.RecipientRestoringContext(
            localIdentifiers: .forUnitTests,
            startDate: Date(),
            remoteConfig: RemoteConfig(clockSkew: 0, valueFlags: [:]),
            attachmentByteCounter: BackupArchiveAttachmentByteCounter(),
            isPrimaryDevice: true,
            tx: tx,
        ))
    }

    private func folder(id: UUID = UUID(), type: BackupProto_ChatFolder.FolderType = .custom) -> BackupProto_ChatFolder {
        var proto = BackupProto_ChatFolder()
        proto.id = id.data
        proto.name = type == .all ? "" : "Work"
        proto.folderType = type
        proto.showMutedChats = true
        proto.includeAllIndividualChats = type == .all
        proto.includeAllGroupChats = type == .all
        return proto
    }

    private func expectSuccess(_ result: BackupArchive.RestoreFrameResult) {
        guard case .success = result else {
            Issue.record("Expected successful restore")
            return
        }
    }
}

private class FrameStream: BackupArchiveOutputStream {
    var frames = [BackupProto_Frame]()
    func writeHeader(_ header: BackupProto_BackupInfo) throws {}
    func writeFrame(_ frame: BackupProto_Frame, flush: BackupArchiveFlushBehavior?) throws { frames.append(frame) }
    func closeFileStream() throws {}
}

private struct NoopMemorySampler: MemorySampler {
    func sample() {}
}
