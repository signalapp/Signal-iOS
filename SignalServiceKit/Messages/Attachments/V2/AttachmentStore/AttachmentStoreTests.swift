//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class AttachmentStoreTests: XCTestCase {

    private var db: InMemoryDB!

    private var attachmentStore: AttachmentStoreImpl!

    override func setUp() async throws {
        db = InMemoryDB()
        attachmentStore = AttachmentStoreImpl()
    }

    // MARK: - Inserts

    func testInsert() throws {
        let attachmentBuilder = randomAttachmentBuilder()
        let referenceBuilder = randomAttachmentReferenceBuilder(
            owner: .thread(.globalThreadWallpaperImage(creationTimestamp: Date().ows_millisecondsSince1970))
        )

        try db.write { tx in
            try attachmentStore.insert(
                attachmentBuilder,
                reference: referenceBuilder,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
        }

        let (references, attachments) = db.read { tx in
            let references = attachmentStore.fetchReferences(
                owners: [.globalThreadWallpaperImage],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            let attachments = attachmentStore.fetch(
                ids: references.map(\.attachmentRowId),
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            return (references, attachments)
        }

        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(attachments.count, 1)

        let reference = references[0]
        let attachment = attachments[0]

        XCTAssertEqual(reference.attachmentRowId, attachment.id)

        assertEqual(attachmentBuilder, attachment)
        try assertEqual(referenceBuilder, reference)
    }

    func testMultipleInserts() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()
        let (threadId2, messageId2) = insertThreadAndInteraction()
        let (threadId3, messageId3) = insertThreadAndInteraction()

        let message1AttachmentIds: [UUID] = [.init()]
        let message2AttachmentIds: [UUID] = [.init(), .init()]
        let message3AttachmentIds: [UUID] = [.init(), .init(), .init()]

        var attachmentIdToAttachmentBuilder = [String: Attachment.ConstructionParams]()
        var attachmentIdToAttachmentReferenceBuilder = [String: AttachmentReference.ConstructionParams]()

        try db.write { tx in
            for (messageId, threadId, attachmentIds) in [
                (messageId1, threadId1, message1AttachmentIds),
                (messageId2, threadId2, message2AttachmentIds),
                (messageId3, threadId3, message3AttachmentIds),
            ] {
                try attachmentIds.enumerated().forEach { (index, id) in
                    let attachmentBuilder = randomAttachmentBuilder()
                    let attachmentReferenceBuilder = randomMessageBodyAttachmentReferenceBuilder(
                        messageRowId: messageId,
                        threadRowId: threadId,
                        orderInOwner: UInt32(index),
                        idInOwner: id.uuidString
                    )
                    try attachmentStore.insert(
                        attachmentBuilder,
                        reference: attachmentReferenceBuilder,
                        db: InMemoryDB.shimOnlyBridge(tx).db,
                        tx: tx
                    )
                    attachmentIdToAttachmentBuilder[id.uuidString] = attachmentBuilder
                    attachmentIdToAttachmentReferenceBuilder[id.uuidString] = attachmentReferenceBuilder
                }
            }
        }

        for (messageId, attachmentIds) in [
            (messageId1, message1AttachmentIds),
            (messageId2, message2AttachmentIds),
            (messageId3, message3AttachmentIds),
        ] {
            let (references, attachments) = db.read { tx in
                let references = attachmentStore.fetchReferences(
                    owners: [.messageBodyAttachment(messageRowId: messageId)],
                    db: InMemoryDB.shimOnlyBridge(tx).db,
                    tx: tx
                )
                let attachments = attachmentStore.fetch(
                    ids: references.map(\.attachmentRowId),
                    db: InMemoryDB.shimOnlyBridge(tx).db,
                    tx: tx
                )
                return (references, attachments)
            }

            XCTAssertEqual(references.count, attachmentIds.count)
            XCTAssertEqual(attachments.count, attachmentIds.count)

            for (reference, attachment) in zip(references, attachments) {
                XCTAssertEqual(reference.attachmentRowId, attachment.id)

                let attachmentId: String
                switch reference.owner {
                case .message(.bodyAttachment(let metadata)):
                    attachmentId = metadata.idInOwner!
                default:
                    XCTFail("Unexpected owner type")
                    continue
                }

                guard
                    let attachmentBuilder = attachmentIdToAttachmentBuilder[attachmentId],
                    let referenceBuilder = attachmentIdToAttachmentReferenceBuilder[attachmentId]
                else {
                    XCTFail("Unexpected attachment id")
                    continue
                }

                assertEqual(attachmentBuilder, attachment)
                try assertEqual(referenceBuilder, reference)
            }
        }
    }

    func testInsertSamePlaintextHash() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()
        let (threadId2, messageId2) = insertThreadAndInteraction()

        // Same content hash for 2 attachments.
        let sha256ContentHash = UUID().data

        let attachmentBuilder1 = randomAttachmentStreamBuilder(sha256ContentHash: sha256ContentHash)
        let attachmentBuilder2 = randomAttachmentStreamBuilder(sha256ContentHash: sha256ContentHash)

        try db.write { tx in
            let attachmentReferenceBuilder1 = randomMessageBodyAttachmentReferenceBuilder(
                messageRowId: messageId1,
                threadRowId: threadId1
            )
            let attachmentReferenceBuilder2 = randomMessageBodyAttachmentReferenceBuilder(
                messageRowId: messageId2,
                threadRowId: threadId2
            )
            try attachmentStore.insert(
                attachmentBuilder1,
                reference: attachmentReferenceBuilder1,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            try attachmentStore.insert(
                attachmentBuilder2,
                reference: attachmentReferenceBuilder2,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
        }

        let (
            message1References,
            message1Attachments,
            message2References,
            message2Attachments
        ) = db.read { tx in
            let message1References = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            let message1Attachments = attachmentStore.fetch(
                ids: message1References.map(\.attachmentRowId),
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            let message2References = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId2)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            let message2Attachments = attachmentStore.fetch(
                ids: message1References.map(\.attachmentRowId),
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            return (message1References, message1Attachments, message2References, message2Attachments)
        }

        // Both messages should have one reference, to one attachment.
        XCTAssertEqual(message1References.count, 1)
        XCTAssertEqual(message1Attachments.count, 1)
        XCTAssertEqual(message2References.count, 1)
        XCTAssertEqual(message2Attachments.count, 1)

        // But the attachments should be the same!
        XCTAssertEqual(message1Attachments[0].id, message2Attachments[0].id)

        // And it should have used the first attachment inserted.
        XCTAssertEqual(message1Attachments[0].encryptionKey, attachmentBuilder1.encryptionKey)
    }

    func testReinsertGlobalThreadAttachment() throws {
        let attachmentBuilder1 = randomAttachmentBuilder()
        let date1 = Date()
        let referenceBuilder1 = randomAttachmentReferenceBuilder(
            owner: .thread(.globalThreadWallpaperImage(creationTimestamp: date1.ows_millisecondsSince1970))
        )
        let attachmentBuilder2 = randomAttachmentBuilder()
        let date2 = date1.addingTimeInterval(100)
        let referenceBuilder2 = randomAttachmentReferenceBuilder(
            owner: .thread(.globalThreadWallpaperImage(creationTimestamp: date2.ows_millisecondsSince1970))
        )

        try db.write { tx in
            try attachmentStore.insert(
                attachmentBuilder1,
                reference: referenceBuilder1,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            // Insert which should overwrite the existing row.
            try attachmentStore.insert(
                attachmentBuilder2,
                reference: referenceBuilder2,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
        }

        let (references, attachments) = db.read { tx in
            let references = attachmentStore.fetchReferences(
                owners: [.globalThreadWallpaperImage],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            let attachments = attachmentStore.fetch(
                ids: references.map(\.attachmentRowId),
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            return (references, attachments)
        }

        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(attachments.count, 1)

        let reference = references[0]
        let attachment = attachments[0]

        XCTAssertEqual(reference.attachmentRowId, attachment.id)

        assertEqual(attachmentBuilder2, attachment)
        try assertEqual(referenceBuilder2, reference)
    }

    func testInsertOverflowTimestamp() throws {
        let (threadId, messageId) = insertThreadAndInteraction()

        // Intentionally overflow
        let receivedAtTimestamp: UInt64 = .max

        OWSAssertionError.test_skipAssertions = true
        defer { OWSAssertionError.test_skipAssertions = false }

        do {
            try db.write { tx in
                let attachmentBuilder = randomAttachmentBuilder()
                let attachmentReferenceBuilder = randomMessageBodyAttachmentReferenceBuilder(
                    messageRowId: messageId,
                    threadRowId: threadId,
                    receivedAtTimestamp: receivedAtTimestamp
                )
                try attachmentStore.insert(
                    attachmentBuilder,
                    reference: attachmentReferenceBuilder,
                    db: InMemoryDB.shimOnlyBridge(tx).db,
                    tx: tx
                )
            }
            // We should have failed! not failing is bad!
            XCTFail("Should throw error on overflowed timestamp")
        } catch {
            // We should have failed! success!
        }

        do {
            try db.write { tx in
                let attachmentBuilder = randomAttachmentBuilder()
                let attachmentReferenceBuilder = randomAttachmentReferenceBuilder(
                    owner: .thread(.globalThreadWallpaperImage(creationTimestamp: receivedAtTimestamp))
                )
                try attachmentStore.insert(
                    attachmentBuilder,
                    reference: attachmentReferenceBuilder,
                    db: InMemoryDB.shimOnlyBridge(tx).db,
                    tx: tx
                )
            }
            // We should have failed! not failing is bad!
            XCTFail("Should throw error on overflowed timestamp")
        } catch {
            // We should have failed! success!
        }
    }

    // MARK: - Enumerate

    func testEnumerateAttachmentReferences() throws {
        let threadIdAndMessageIds = (0..<5).map { _ in
            insertThreadAndInteraction()
        }

        // Insert many references to the same builder over and over.
        let attachmentBuilder = randomAttachmentBuilder()

        let attachmentIdsInOwner: [String] = try db.write { tx in
            return try threadIdAndMessageIds.flatMap { threadId, messageId in
                return try (0..<5).map { index in
                    let attachmentIdInOwner = UUID().uuidString
                    let attachmentReferenceBuilder = randomMessageBodyAttachmentReferenceBuilder(
                        messageRowId: messageId,
                        threadRowId: threadId,
                        orderInOwner: UInt32(index),
                        idInOwner: attachmentIdInOwner
                    )
                    try attachmentStore.insert(
                        attachmentBuilder,
                        reference: attachmentReferenceBuilder,
                        db: InMemoryDB.shimOnlyBridge(tx).db,
                        tx: tx
                    )
                    return attachmentIdInOwner
                }
            }
        }

        // Get the attachment id we just inserted.
        let attachmentId = db.read { tx in
            let references = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: threadIdAndMessageIds[0].interactionRowId)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            let attachment = attachmentStore.fetch(
                ids: references.map(\.attachmentRowId),
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            return attachment.first!.id
        }

        // Insert some other references to other arbitrary attachments
        try db.write { tx in
            try threadIdAndMessageIds.forEach { threadId, messageId in
                try (0..<5).forEach { index in
                    let attachmentReferenceBuilder = randomMessageBodyAttachmentReferenceBuilder(
                        messageRowId: messageId,
                        threadRowId: threadId,
                        orderInOwner: UInt32(index)
                    )
                    try attachmentStore.insert(
                        randomAttachmentBuilder(),
                        reference: attachmentReferenceBuilder,
                        db: InMemoryDB.shimOnlyBridge(tx).db,
                        tx: tx
                    )
                }
            }
        }

        // Check that we enumerate all the ids we created for the original attachment's id.
        var enumeratedCount = 0
        db.read { tx in
            attachmentStore.enumerateAllReferences(
                toAttachmentId: attachmentId,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx,
                block: { reference in
                    enumeratedCount += 1

                    XCTAssertEqual(reference.attachmentRowId, attachmentId)

                    switch reference.owner {
                    case .message(.bodyAttachment(let metadata)):
                        XCTAssertTrue(attachmentIdsInOwner.contains(metadata.idInOwner!))
                    default:
                        XCTFail("Unexpected attachment type!")
                    }
                }
            )
        }

        XCTAssertEqual(enumeratedCount, attachmentIdsInOwner.count)
    }

    // MARK: - Update

    func testUpdateReceivedAtTimestamp() throws {
        let (threadId, messageId) = insertThreadAndInteraction()

        let initialReceivedAtTimestamp: UInt64 = 1000

        try db.write { tx in
            let attachmentBuilder = randomAttachmentBuilder()
            let attachmentReferenceBuilder = randomMessageBodyAttachmentReferenceBuilder(
                messageRowId: messageId,
                threadRowId: threadId,
                receivedAtTimestamp: initialReceivedAtTimestamp
            )
            try attachmentStore.insert(
                attachmentBuilder,
                reference: attachmentReferenceBuilder,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
        }

        var reference = db.read { tx in
            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first!
        }

        switch reference.owner {
        case .message(.bodyAttachment(let metadata)):
            XCTAssertEqual(metadata.receivedAtTimestamp, initialReceivedAtTimestamp)
        default:
            XCTFail("Unexpected reference type!")
        }

        let changedReceivedAtTimestamp = initialReceivedAtTimestamp + 100

        // Update and refetch the reference.
        reference = try db.write { tx in
            try attachmentStore.update(
                reference,
                withReceivedAtTimestamp: changedReceivedAtTimestamp,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )

            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first!
        }

        switch reference.owner {
        case .message(.bodyAttachment(let metadata)):
            XCTAssertEqual(metadata.receivedAtTimestamp, changedReceivedAtTimestamp)
        default:
            XCTFail("Unexpected reference type!")
        }
    }

    // MARK: - Remove Owner

    func testRemoveOwner() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()
        let (threadId2, messageId2) = insertThreadAndInteraction()

        // Create two references to the same attachment.
        let attachmentBuilder = randomAttachmentBuilder()

        try db.write { tx in
            try attachmentStore.insert(
                attachmentBuilder,
                reference: randomMessageBodyAttachmentReferenceBuilder(
                    messageRowId: messageId1,
                    threadRowId: threadId1
                ),
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
            try attachmentStore.insert(
                attachmentBuilder,
                reference: randomMessageBodyAttachmentReferenceBuilder(
                    messageRowId: messageId2,
                    threadRowId: threadId2
                ),
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
        }

        let (reference1, reference2) = db.read { tx in
            let reference1 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first!
            let reference2 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId2)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first!
            return (reference1, reference2)
        }

        XCTAssertEqual(reference1.attachmentRowId, reference2.attachmentRowId)

        try db.write { tx in
            // Remove the first reference.
            try attachmentStore.removeOwner(
                reference1.owner.id,
                for: reference1.attachmentRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )

            // The attachment should still exist.
            XCTAssertNotNil(attachmentStore.fetch(
                ids: [reference1.attachmentRowId],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first)

            // Remove the second reference.
            try attachmentStore.removeOwner(
                reference2.owner.id,
                for: reference2.attachmentRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )

            // The attachment should no longer exist.
            XCTAssertNil(attachmentStore.fetch(
                ids: [reference1.attachmentRowId],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first)
        }
    }

    // MARK: - Duplication

    func testDuplicateOwner() throws {
        let (threadId, messageId1, messageId2) = db.write { tx in
            let thread = insertThread(tx: tx)
            return (
                thread.sqliteRowId!,
                insertInteraction(thread: thread, tx: tx),
                insertInteraction(thread: thread, tx: tx)
            )
        }

        let originalReferenceBuilder = randomMessageBodyAttachmentReferenceBuilder(
            messageRowId: messageId1,
            threadRowId: threadId
        )

        try db.write { tx in
            let attachmentBuilder = randomAttachmentBuilder()
            try attachmentStore.insert(
                attachmentBuilder,
                reference: originalReferenceBuilder,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
        }

        // Get the attachment we just inserted
        let reference1 = db.read { tx in
            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first!
        }

        // Create a copy reference.
        try db.write { tx in
            try attachmentStore.addOwner(
                duplicating: reference1,
                withNewOwner: .messageBodyAttachment(messageRowId: messageId2),
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
        }

        // Check that the copy was created correctly.
        let newReference = db.read { tx in
            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId2)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first!
        }

        XCTAssertEqual(newReference.attachmentRowId, reference1.attachmentRowId)
    }

    func testDuplicateOwnersInvalid() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()
        let (_, messageId2) = insertThreadAndInteraction()

        let originalReferenceBuilder = randomMessageBodyAttachmentReferenceBuilder(
            messageRowId: messageId1,
            threadRowId: threadId1
        )

        try db.write { tx in
            let attachmentBuilder = randomAttachmentBuilder()
            try attachmentStore.insert(
                attachmentBuilder,
                reference: originalReferenceBuilder,
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            )
        }

        // Get the attachment we just inserted
        let reference1 = db.read { tx in
            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                db: InMemoryDB.shimOnlyBridge(tx).db,
                tx: tx
            ).first!
        }

        OWSAssertionError.test_skipAssertions = true
        defer { OWSAssertionError.test_skipAssertions = false }

        // If we try and duplicate to an owner on another thread, that should fail.
        do {
            try db.write { tx in
                try attachmentStore.addOwner(
                    duplicating: reference1,
                    withNewOwner: .messageBodyAttachment(messageRowId: messageId2),
                    db: InMemoryDB.shimOnlyBridge(tx).db,
                    tx: tx
                )
            }
            // We should have failed!
            XCTFail("Should have failed inserting invalid reference")
        } catch {
            // Good, we threw an error
        }

        // If we try and duplicate to an owner of a different type (thread), that should fail.
        do {
            try db.write { tx in
                try attachmentStore.addOwner(
                    duplicating: reference1,
                    withNewOwner: .threadWallpaperImage(threadRowId: threadId1),
                    db: InMemoryDB.shimOnlyBridge(tx).db,
                    tx: tx
                )
            }
            // We should have failed!
            XCTFail("Should have failed inserting invalid reference")
        } catch {
            // Good, we threw an error
        }
    }

    // MARK: - Helpers

    private func insertThreadAndInteraction() -> (threadRowId: Int64, interactionRowId: Int64) {
        return db.write { tx in
            let thread = insertThread(tx: tx)
            let interactionRowId = insertInteraction(thread: thread, tx: tx)
            return (thread.sqliteRowId!, interactionRowId)
        }
    }

    private func insertThread(tx: DBWriteTransaction) -> TSThread {
        let thread = TSThread(uniqueId: UUID().uuidString)
        try! thread.asRecord().insert(InMemoryDB.shimOnlyBridge(tx).db)
        return thread
    }

    private func insertInteraction(thread: TSThread, tx: DBWriteTransaction) -> Int64 {
        let interaction = TSInteraction(uniqueId: UUID().uuidString, thread: thread)
        try! interaction.asRecord().insert(InMemoryDB.shimOnlyBridge(tx).db)
        return interaction.sqliteRowId!
    }

    private func randomAttachmentBuilder() -> Attachment.ConstructionParams {
        return Attachment.ConstructionParams.fromPointer(
            blurHash: UUID().uuidString,
            mimeType: "image/png",
            encryptionKey: UUID().data,
            transitTierInfo: .init(
                cdnNumber: 3,
                cdnKey: UUID().uuidString,
                uploadTimestamp: Date().ows_millisecondsSince1970,
                encryptionKey: UUID().data,
                encryptedByteCount: 10,
                digestSHA256Ciphertext: UUID().data,
                lastDownloadAttemptTimestamp: nil
            )
        )
    }

    private func randomAttachmentStreamBuilder(
        sha256ContentHash: Data = UUID().data
    ) -> Attachment.ConstructionParams {
        return Attachment.ConstructionParams.fromStream(
            blurHash: UUID().uuidString,
            mimeType: "image/png",
            encryptionKey: UUID().data,
            streamInfo: .init(
                sha256ContentHash: sha256ContentHash,
                encryptedByteCount: 110,
                unencryptedByteCount: 100,
                contentType: .file,
                digestSHA256Ciphertext: UUID().data,
                localRelativeFilePath: UUID().uuidString
            ),
            mediaName: UUID().uuidString
        )
    }

    private func randomAttachmentReferenceBuilder(owner: AttachmentReference.Owner) -> AttachmentReference.ConstructionParams {
        return AttachmentReference.ConstructionParams(
            owner: owner,
            sourceFilename: nil,
            sourceUnencryptedByteCount: 12,
            sourceMediaSizePixels: CGSize(width: 100, height: 100)
        )
    }

    private func randomMessageBodyAttachmentReferenceBuilder(
        messageRowId: Int64,
        threadRowId: Int64,
        receivedAtTimestamp: UInt64? = nil,
        orderInOwner: UInt32 = 0,
        idInOwner: String? = nil
    ) -> AttachmentReference.ConstructionParams {
        return AttachmentReference.ConstructionParams(
            owner: .message(.bodyAttachment(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: receivedAtTimestamp ?? Date().ows_millisecondsSince1970,
                threadRowId: threadRowId,
                contentType: .image,
                caption: nil,
                renderingFlag: .default,
                orderInOwner: orderInOwner,
                idInOwner: idInOwner
            ))),
            sourceFilename: nil,
            sourceUnencryptedByteCount: 12,
            sourceMediaSizePixels: CGSize(width: 100, height: 100)
        )
    }

    private func assertEqual(_ builder: Attachment.ConstructionParams, _ attachment: Attachment) {
        var record = Attachment.Record(attachmentBuilder: builder)
        record.sqliteId = attachment.id
        XCTAssertEqual(record, .init(attachment: attachment))
    }

    private func assertEqual(_ builder: AttachmentReference.ConstructionParams, _ reference: AttachmentReference) throws {
        switch (builder.owner, reference.owner) {
        case (.message, .message(let messageSource)):
            XCTAssertEqual(
                try builder.buildRecord(attachmentRowId: reference.attachmentRowId)
                    as! AttachmentReference.MessageAttachmentReferenceRecord,
                AttachmentReference.MessageAttachmentReferenceRecord(attachmentReference: reference, messageSource: messageSource)
            )
        case (.storyMessage, .storyMessage(let storyMessageSource)):
            XCTAssertEqual(
                try builder.buildRecord(attachmentRowId: reference.attachmentRowId)
                    as! AttachmentReference.StoryMessageAttachmentReferenceRecord,
                try AttachmentReference.StoryMessageAttachmentReferenceRecord(
                    attachmentReference: reference,
                    storyMessageSource: storyMessageSource
                )
            )
        case (.thread, .thread(let threadSource)):
            XCTAssertEqual(
                try builder.buildRecord(attachmentRowId: reference.attachmentRowId)
                    as! AttachmentReference.ThreadAttachmentReferenceRecord,
                AttachmentReference.ThreadAttachmentReferenceRecord(attachmentReference: reference, threadSource: threadSource)
            )
        case (.message, _), (.storyMessage, _), (.thread, _):
            XCTFail("Non matching owner types")
        }
    }
}
