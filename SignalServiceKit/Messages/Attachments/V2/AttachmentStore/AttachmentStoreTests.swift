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
    private var attachmentUploadStore: AttachmentUploadStoreImpl!

    override func setUp() async throws {
        db = InMemoryDB()
        attachmentStore = AttachmentStoreImpl()
        attachmentUploadStore = AttachmentUploadStoreImpl(attachmentStore: attachmentStore)
    }

    // MARK: - Inserts

    func testInsert() throws {
        let attachmentParams = Attachment.ConstructionParams.mockPointer()
        let referenceParams = AttachmentReference.ConstructionParams.mock(
            owner: .thread(.globalThreadWallpaperImage(creationTimestamp: Date().ows_millisecondsSince1970))
        )

        try db.write { tx in
            try attachmentStore.insert(
                attachmentParams,
                reference: referenceParams,
                tx: tx
            )
        }

        let (references, attachments) = db.read { tx in
            let references = attachmentStore.fetchReferences(
                owners: [.globalThreadWallpaperImage],
                tx: tx
            )
            let attachments = attachmentStore.fetch(
                ids: references.map(\.attachmentRowId),
                tx: tx
            )
            return (references, attachments)
        }

        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(attachments.count, 1)

        let reference = references[0]
        let attachment = attachments[0]

        XCTAssertEqual(reference.attachmentRowId, attachment.id)

        assertEqual(attachmentParams, attachment)
        try assertEqual(referenceParams, reference)
    }

    func testMultipleInserts() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()
        let (threadId2, messageId2) = insertThreadAndInteraction()
        let (threadId3, messageId3) = insertThreadAndInteraction()

        let message1AttachmentIds: [UUID] = [.init()]
        let message2AttachmentIds: [UUID] = [.init(), .init()]
        let message3AttachmentIds: [UUID] = [.init(), .init(), .init()]

        var attachmentIdToAttachmentParams = [UUID: Attachment.ConstructionParams]()
        var attachmentIdToAttachmentReferenceParams = [UUID: AttachmentReference.ConstructionParams]()

        try db.write { tx in
            for (messageId, threadId, attachmentIds) in [
                (messageId1, threadId1, message1AttachmentIds),
                (messageId2, threadId2, message2AttachmentIds),
                (messageId3, threadId3, message3AttachmentIds),
            ] {
                try attachmentIds.enumerated().forEach { (index, id) in
                    let attachmentParams = Attachment.ConstructionParams.mockPointer()
                    let attachmentReferenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                        messageRowId: messageId,
                        threadRowId: threadId,
                        orderInOwner: UInt32(index),
                        idInOwner: id
                    )
                    try attachmentStore.insert(
                        attachmentParams,
                        reference: attachmentReferenceParams,
                        tx: tx
                    )
                    attachmentIdToAttachmentParams[id] = attachmentParams
                    attachmentIdToAttachmentReferenceParams[id] = attachmentReferenceParams
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
                    tx: tx
                )
                let attachments = attachmentStore.fetch(
                    ids: references.map(\.attachmentRowId),
                    tx: tx
                )
                return (references, attachments)
            }

            XCTAssertEqual(references.count, attachmentIds.count)
            XCTAssertEqual(attachments.count, attachmentIds.count)

            for (reference, attachment) in zip(references, attachments) {
                XCTAssertEqual(reference.attachmentRowId, attachment.id)

                let attachmentId: UUID
                switch reference.owner {
                case .message(.bodyAttachment(let metadata)):
                    attachmentId = metadata.idInOwner!
                default:
                    XCTFail("Unexpected owner type")
                    continue
                }

                guard
                    let attachmentParams = attachmentIdToAttachmentParams[attachmentId],
                    let referenceParams = attachmentIdToAttachmentReferenceParams[attachmentId]
                else {
                    XCTFail("Unexpected attachment id")
                    continue
                }

                assertEqual(attachmentParams, attachment)
                try assertEqual(referenceParams, reference)
            }
        }
    }

    func testInsertSamePlaintextHash() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()
        let (threadId2, messageId2) = insertThreadAndInteraction()

        // Same content hash for 2 attachments.
        let sha256ContentHash = UUID().data

        let attachmentParams1 = Attachment.ConstructionParams.mockStream(streamInfo: .mock(sha256ContentHash: sha256ContentHash))
        let attachmentParams2 = Attachment.ConstructionParams.mockStream(streamInfo: .mock(sha256ContentHash: sha256ContentHash))

        try db.write { tx in
            let attachmentReferenceParams1 = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                messageRowId: messageId1,
                threadRowId: threadId1
            )
            try attachmentStore.insert(
                attachmentParams1,
                reference: attachmentReferenceParams1,
                tx: tx
            )

            let message1References = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                tx: tx
            )
            let message1Attachment = attachmentStore.fetch(
                ids: message1References.map(\.attachmentRowId),
                tx: tx
            ).first!

            let attachmentReferenceParams2 = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                messageRowId: messageId2,
                threadRowId: threadId2
            )
            do {
                try attachmentStore.insert(
                    attachmentParams2,
                    reference: attachmentReferenceParams2,
                    tx: tx
                )
                XCTFail("Should have thrown error!")
            } catch let error {
                switch error {
                case is AttachmentInsertError:
                    switch error as! AttachmentInsertError {
                    case .duplicatePlaintextHash(let existingAttachmentId):
                        XCTAssertEqual(existingAttachmentId, message1Attachment.id)
                    default:
                        XCTFail("Unexpected error")
                    }
                default:
                    XCTFail("Unexpected error")
                }
            }

            // Try again but insert using explicit owner adding.
            try attachmentStore.addOwner(
                attachmentReferenceParams2,
                for: message1Attachment.id,
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
                tx: tx
            )
            let message1Attachments = attachmentStore.fetch(
                ids: message1References.map(\.attachmentRowId),
                tx: tx
            )
            let message2References = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId2)],
                tx: tx
            )
            let message2Attachments = attachmentStore.fetch(
                ids: message1References.map(\.attachmentRowId),
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
        XCTAssertEqual(message2Attachments[0].encryptionKey, attachmentParams1.encryptionKey)
    }

    func testReinsertGlobalThreadAttachment() throws {
        let attachmentParams1 = Attachment.ConstructionParams.mockPointer()
        let date1 = Date()
        let referenceParams1 = AttachmentReference.ConstructionParams.mock(
            owner: .thread(.globalThreadWallpaperImage(creationTimestamp: date1.ows_millisecondsSince1970))
        )
        let attachmentParams2 = Attachment.ConstructionParams.mockPointer()
        let date2 = date1.addingTimeInterval(100)
        let referenceParams2 = AttachmentReference.ConstructionParams.mock(
            owner: .thread(.globalThreadWallpaperImage(creationTimestamp: date2.ows_millisecondsSince1970))
        )

        try db.write { tx in
            try attachmentStore.insert(
                attachmentParams1,
                reference: referenceParams1,
                tx: tx
            )
            // Insert which should overwrite the existing row.
            try attachmentStore.insert(
                attachmentParams2,
                reference: referenceParams2,
                tx: tx
            )
        }

        let (references, attachments) = db.read { tx in
            let references = attachmentStore.fetchReferences(
                owners: [.globalThreadWallpaperImage],
                tx: tx
            )
            let attachments = attachmentStore.fetch(
                ids: references.map(\.attachmentRowId),
                tx: tx
            )
            return (references, attachments)
        }

        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(attachments.count, 1)

        let reference = references[0]
        let attachment = attachments[0]

        XCTAssertEqual(reference.attachmentRowId, attachment.id)

        assertEqual(attachmentParams2, attachment)
        try assertEqual(referenceParams2, reference)
    }

    func testInsertOverflowTimestamp() throws {
        let (threadId, messageId) = insertThreadAndInteraction()

        // Intentionally overflow
        let receivedAtTimestamp: UInt64 = .max

        OWSAssertionError.test_skipAssertions = true
        defer { OWSAssertionError.test_skipAssertions = false }

        do {
            try db.write { tx in
                let attachmentParams = Attachment.ConstructionParams.mockPointer()
                let attachmentReferenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                    messageRowId: messageId,
                    threadRowId: threadId,
                    receivedAtTimestamp: receivedAtTimestamp
                )
                try attachmentStore.insert(
                    attachmentParams,
                    reference: attachmentReferenceParams,
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
                let attachmentParams = Attachment.ConstructionParams.mockPointer()
                let attachmentReferenceParams = AttachmentReference.ConstructionParams.mock(
                    owner: .thread(.globalThreadWallpaperImage(creationTimestamp: receivedAtTimestamp))
                )
                try attachmentStore.insert(
                    attachmentParams,
                    reference: attachmentReferenceParams,
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

        // Insert many references to the same Params over and over.
        let attachmentParams = Attachment.ConstructionParams.mockStream()

        let attachmentIdsInOwner: [UUID] = try db.write { tx in
            var attachmentRowId: Attachment.IDType?
            return try threadIdAndMessageIds.flatMap { threadId, messageId in
                return try (0..<5).map { index in
                    let attachmentIdInOwner = UUID()
                    let attachmentReferenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                        messageRowId: messageId,
                        threadRowId: threadId,
                        orderInOwner: UInt32(index),
                        idInOwner: attachmentIdInOwner
                    )
                    if let attachmentRowId {
                        try attachmentStore.addOwner(
                            attachmentReferenceParams,
                            for: attachmentRowId,
                            tx: tx
                        )
                    } else {
                        try attachmentStore.insert(
                            attachmentParams,
                            reference: attachmentReferenceParams,
                            tx: tx
                        )
                        attachmentRowId = tx.db.lastInsertedRowID
                    }
                    return attachmentIdInOwner
                }
            }
        }

        // Get the attachment id we just inserted.
        let attachmentId = db.read { tx in
            let references = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: threadIdAndMessageIds[0].interactionRowId)],
                tx: tx
            )
            let attachment = attachmentStore.fetch(
                ids: references.map(\.attachmentRowId),
                tx: tx
            )
            return attachment.first!.id
        }

        // Insert some other references to other arbitrary attachments
        try db.write { tx in
            try threadIdAndMessageIds.forEach { threadId, messageId in
                try (0..<5).forEach { index in
                    let attachmentReferenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                        messageRowId: messageId,
                        threadRowId: threadId,
                        orderInOwner: UInt32(index)
                    )
                    try attachmentStore.insert(
                        Attachment.ConstructionParams.mockPointer(),
                        reference: attachmentReferenceParams,
                        tx: tx
                    )
                }
            }
        }

        // Check that we enumerate all the ids we created for the original attachment's id.
        var enumeratedCount = 0
        try db.read { tx in
            try attachmentStore.enumerateAllReferences(
                toAttachmentId: attachmentId,
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

    func testEnumerateAttachmentsWithMediaName() throws {
        let attachmentCount = 100

        let threadIds = db.write { tx in
            (0..<attachmentCount).map { _ in
                insertThread(tx: tx).sqliteRowId!
            }
        }

        try db.write { tx in
            try threadIds.forEach { threadId in
                try attachmentStore.insert(
                    .mockStream(),
                    reference: .mock(owner: .thread(.threadWallpaperImage(.init(threadRowId: threadId, creationTimestamp: 0)))),
                    tx: tx
                )
            }
        }

        // Check that we enumerate all the ids we created for the original attachment's id.
        var enumeratedCount = 0
        try db.read { tx in
            try attachmentStore.enumerateAllAttachmentsWithMediaName(
                tx: tx,
                block: { _ in
                    enumeratedCount += 1
                }
            )
        }

        XCTAssertEqual(enumeratedCount, attachmentCount)
    }

    func testOldestStickerPackReferences() throws {
        // Sticker pack id to oldest row id.
        var stickerPackIds = [Data: Int64]()

        try db.write { tx in
            let thread = insertThread(tx: tx)
            let threadRowId = thread.sqliteRowId!

            // Add some non sticker attachments.
            for _ in 0..<10 {
                let messageRowId = insertInteraction(thread: thread, tx: tx)

                try attachmentStore.insert(
                    .mockStream(),
                    reference: .mock(
                        owner: .message(.bodyAttachment(.init(
                            messageRowId: messageRowId,
                            receivedAtTimestamp: .random(in: 0..<9999999),
                            threadRowId: threadRowId,
                            contentType: .image,
                            isPastEditRevision: false,
                            caption: nil,
                            renderingFlag: .default,
                            orderInOwner: 0,
                            idInOwner: nil,
                            isViewOnce: false
                        )))),
                    tx: tx
                )
            }

            // Add some sticker attachments
            for _ in 0..<10 {
                let packId = UUID().data
                // Each sticker pack gets multiple stickers, but we should
                // dedupe down to the pack IDs.
                let numStickersInPack = Int.random(in: 1...10)
                for _ in 0..<numStickersInPack {
                    let stickerId = UInt32.random(in: 0..<UInt32.max)

                    let messageRowId = insertInteraction(thread: thread, tx: tx)

                    try attachmentStore.insert(
                        .mockStream(),
                        reference: .mock(
                            owner: .message(.sticker(.init(
                                messageRowId: messageRowId,
                                receivedAtTimestamp: .random(in: 0..<9999999),
                                threadRowId: threadRowId,
                                contentType: .image,
                                isPastEditRevision: false,
                                stickerPackId: packId,
                                stickerId: stickerId
                            )))),
                        tx: tx
                    )

                    stickerPackIds[packId] = min(messageRowId, stickerPackIds[packId] ?? .max)
                }
            }
        }

        let readPackReferences =  try db.read { tx in
            try attachmentStore.oldestStickerPackReferences(tx: tx)
        }

        XCTAssertEqual(readPackReferences.count, stickerPackIds.count)
        readPackReferences.forEach { packRef in
            XCTAssertEqual(packRef.messageRowId, stickerPackIds[packRef.stickerPackId])
        }

    }

    // MARK: - Update

    func testUpdateReceivedAtTimestamp() throws {
        let (threadId, messageId) = insertThreadAndInteraction()

        let initialReceivedAtTimestamp: UInt64 = 1000

        try db.write { tx in
            let attachmentParams = Attachment.ConstructionParams.mockPointer()
            let attachmentReferenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                messageRowId: messageId,
                threadRowId: threadId,
                receivedAtTimestamp: initialReceivedAtTimestamp
            )
            try attachmentStore.insert(
                attachmentParams,
                reference: attachmentReferenceParams,
                tx: tx
            )
        }

        var reference = db.read { tx in
            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId)],
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
                tx: tx
            )

            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId)],
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

    func testMarkAsUploaded() throws {
        let (threadId, messageId) = insertThreadAndInteraction()

        try db.write { tx in
            let attachmentParams = Attachment.ConstructionParams.mockStream()
            let attachmentReferenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                messageRowId: messageId,
                threadRowId: threadId
            )
            try attachmentStore.insert(
                attachmentParams,
                reference: attachmentReferenceParams,
                tx: tx
            )
        }

        func fetchAttachment() -> Attachment {
            return db.read { tx in
                let references = attachmentStore.fetchReferences(
                    owners: [.messageBodyAttachment(messageRowId: messageId)],
                    tx: tx
                )
                return attachmentStore.fetch(
                    ids: references.map(\.attachmentRowId),
                    tx: tx
                ).first!
            }
        }

        var attachment = fetchAttachment()

        guard let stream = attachment.asStream() else {
            XCTFail("Expected attachment stream!")
            return
        }
        XCTAssertNil(attachment.transitTierInfo)

        let transitTierInfo = Attachment.TransitTierInfo(
            cdnNumber: 3,
            cdnKey: UUID().uuidString,
            uploadTimestamp: Date().ows_millisecondsSince1970,
            encryptionKey: UUID().data,
            unencryptedByteCount: 100,
            digestSHA256Ciphertext: UUID().data,
            incrementalMacInfo: nil,
            lastDownloadAttemptTimestamp: nil
        )

        // Mark it as uploaded.
        try db.write { tx in
            try attachmentUploadStore.markUploadedToTransitTier(
                attachmentStream: stream,
                info: transitTierInfo,
                tx: tx
            )
        }

        // Refetch and check that it is appropriately marked.
        attachment = fetchAttachment()

        XCTAssertEqual(attachment.transitTierInfo, transitTierInfo)
    }

    // MARK: - Remove Owner

    func testRemoveOwner() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()
        let (threadId2, messageId2) = insertThreadAndInteraction()

        // Create two references to the same attachment.
        let attachmentParams = Attachment.ConstructionParams.mockStream()

        try db.write { tx in
            try attachmentStore.insert(
                attachmentParams,
                reference: AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                    messageRowId: messageId1,
                    threadRowId: threadId1
                ),
                tx: tx
            )
            let attachmentId = tx.db.lastInsertedRowID
            try attachmentStore.addOwner(
                AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                    messageRowId: messageId2,
                    threadRowId: threadId2
                ),
                for: attachmentId,
                tx: tx
            )
        }

        let (reference1, reference2) = db.read { tx in
            let reference1 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                tx: tx
            ).first!
            let reference2 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId2)],
                tx: tx
            ).first!
            return (reference1, reference2)
        }

        XCTAssertEqual(reference1.attachmentRowId, reference2.attachmentRowId)

        try db.write { tx in
            // Remove the first reference.
            try attachmentStore.removeOwner(
                reference: reference1,
                tx: tx
            )

            // The attachment should still exist.
            XCTAssertNotNil(attachmentStore.fetch(
                ids: [reference1.attachmentRowId],
                tx: tx
            ).first)

            // Remove the second reference.
            try attachmentStore.removeOwner(
                reference: reference2,
                tx: tx
            )

            // The attachment should no longer exist.
            XCTAssertNil(attachmentStore.fetch(
                ids: [reference1.attachmentRowId],
                tx: tx
            ).first)
        }
    }

    func testRemoveOwner_sameOwnerMultipleReferences() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()

        let referenceUUID1 = UUID()
        let referenceUUID2 = UUID()

        // Create two references to the same attachment on the same message.
        let attachmentParams = Attachment.ConstructionParams.mockStream()

        try db.write { tx in
            try attachmentStore.insert(
                attachmentParams,
                reference: AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                    messageRowId: messageId1,
                    threadRowId: threadId1,
                    orderInOwner: 0,
                    idInOwner: referenceUUID1
                ),
                tx: tx
            )
            let attachmentId = tx.db.lastInsertedRowID
            try attachmentStore.addOwner(
                AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                    messageRowId: messageId1,
                    threadRowId: threadId1,
                    orderInOwner: 1,
                    idInOwner: referenceUUID2
                ),
                for: attachmentId,
                tx: tx
            )
        }

        let (reference1, reference2) = db.read { tx in
            let references = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                tx: tx
            ).sorted(by: {
                $0.orderInOwningMessage! < $1.orderInOwningMessage!
            })
            return (references[0], references[1])
        }

        func checkIdInOwner(of reference: AttachmentReference, matches uuid: UUID) {
            switch reference.owner {
            case .message(let messageSource):
                switch messageSource {
                case .bodyAttachment(let metadata):
                    XCTAssertEqual(metadata.idInOwner, uuid)
                default:
                    XCTFail("Unexpected reference type")
                }
            default:
                XCTFail("Unexpected reference type")
            }
        }

        checkIdInOwner(of: reference1, matches: referenceUUID1)
        checkIdInOwner(of: reference2, matches: referenceUUID2)

        try db.write { tx in
            // Remove the first reference.
            try attachmentStore.removeOwner(
                reference: reference1,
                tx: tx
            )

            // The attachment should still exist.
            XCTAssertNotNil(attachmentStore.fetch(
                ids: [reference1.attachmentRowId],
                tx: tx
            ).first)

            // Refetch references
            let references = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                tx: tx
            )
            XCTAssertEqual(references.count, 1)
            checkIdInOwner(of: references[0], matches: referenceUUID2)
        }
    }

    // MARK: Remove all thread owners

    func testRemoveAllThreadOwners() throws {
        var threadRowIds: [Int64?] = [nil]
        db.write { tx in
            for _ in 0..<5 {
                threadRowIds.append(self.insertThread(tx: tx).sqliteRowId!)
            }
        }

        try db.write { tx in
            try threadRowIds.forEach { threadRowId in
                let attachmentParams = Attachment.ConstructionParams.mockPointer()
                let timestamp = Date().ows_millisecondsSince1970
                let referenceParams = AttachmentReference.ConstructionParams.mock(
                    owner: .thread(threadRowId.map {
                        .threadWallpaperImage(.init(threadRowId: $0, creationTimestamp: timestamp))
                    } ?? .globalThreadWallpaperImage(creationTimestamp: timestamp))
                )
                try attachmentStore.insert(
                    attachmentParams,
                    reference: referenceParams,
                    tx: tx
                )
            }
        }

        func assertAttachmentCount(_ expectedCount: Int) {
            db.read { tx in
                let references = attachmentStore.fetchReferences(
                    owners: threadRowIds.map { threadRowId in
                        threadRowId.map {
                            .threadWallpaperImage(threadRowId: $0)
                        } ?? .globalThreadWallpaperImage
                    },
                    tx: tx
                )
                let attachments = attachmentStore.fetch(
                    ids: references.map(\.attachmentRowId),
                    tx: tx
                )
                XCTAssertEqual(references.count, expectedCount)
                XCTAssertEqual(attachments.count, expectedCount)
            }
        }

        assertAttachmentCount(threadRowIds.count)

        // Remove all and count should be 0.

        try db.write { tx in
            try attachmentStore.removeAllThreadOwners(
                tx: tx
            )
        }

        assertAttachmentCount(0)
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

        let originalReferenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
            messageRowId: messageId1,
            threadRowId: threadId
        )

        try db.write { tx in
            let attachmentParams = Attachment.ConstructionParams.mockPointer()
            try attachmentStore.insert(
                attachmentParams,
                reference: originalReferenceParams,
                tx: tx
            )
        }

        // Get the attachment we just inserted
        let reference1 = db.read { tx in
            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                tx: tx
            ).first!
        }

        // Create a copy reference.
        try db.write { tx in
            switch reference1.owner {
            case .message(let reference1MessageSource):
                try attachmentStore.duplicateExistingMessageOwner(
                    reference1MessageSource,
                    with: reference1,
                    newOwnerMessageRowId: messageId2,
                    newOwnerThreadRowId: threadId,
                    newOwnerIsPastEditRevision: false,
                    tx: tx
                )
            default:
                XCTFail("Unexpected reference owner type")
            }
        }

        // Check that the copy was created correctly.
        let newReference = db.read { tx in
            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId2)],
                tx: tx
            ).first!
        }

        XCTAssertEqual(newReference.attachmentRowId, reference1.attachmentRowId)
    }

    func testDuplicateOwnersInvalid() throws {
        let (threadId1, messageId1) = insertThreadAndInteraction()
        let (threadId2, messageId2) = insertThreadAndInteraction()

        let originalReferenceParams = AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
            messageRowId: messageId1,
            threadRowId: threadId1
        )

        try db.write { tx in
            let attachmentParams = Attachment.ConstructionParams.mockPointer()
            try attachmentStore.insert(
                attachmentParams,
                reference: originalReferenceParams,
                tx: tx
            )
        }

        // Get the attachment we just inserted
        let reference1 = db.read { tx in
            return attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                tx: tx
            ).first!
        }

        OWSAssertionError.test_skipAssertions = true
        defer { OWSAssertionError.test_skipAssertions = false }

        // If we try and duplicate to an owner on another thread, that should fail.
        do {
            try db.write { tx in
                switch reference1.owner {
                case .message(let reference1MessageSource):
                    try attachmentStore.duplicateExistingMessageOwner(
                        reference1MessageSource,
                        with: reference1,
                        newOwnerMessageRowId: messageId2,
                        newOwnerThreadRowId: threadId2,
                        newOwnerIsPastEditRevision: false,
                        tx: tx
                    )
                default:
                    XCTFail("Unexpected reference owner type")
                }
            }
            // We should have failed!
            XCTFail("Should have failed inserting invalid reference")
        } catch {
            // Good, we threw an error
        }
    }

    // MARK: - Thread merging

    func testThreadMerging() throws {
        var threadId1: Int64!
        var threadId2: Int64!
        var threadId3: Int64!
        var messageId1: Int64!
        var messageId2: Int64!
        var messageId3: Int64!
        db.write { tx in
            let thread1 = insertThread(tx: tx)
            threadId1 = thread1.sqliteRowId!
            messageId1 = insertInteraction(thread: thread1, tx: tx)
            messageId2 = insertInteraction(thread: thread1, tx: tx)
            let thread2 = insertThread(tx: tx)
            threadId2 = thread2.sqliteRowId!
            messageId3 = insertInteraction(thread: thread2, tx: tx)
            let thread3 = insertThread(tx: tx)
            threadId3 = thread3.sqliteRowId!
        }

        try db.write { tx in
            for (threadRowId, messageRowId) in [
                (threadId1, messageId1),
                (threadId1, messageId2),
                (threadId2, messageId3)
            ] {
                // Create an attachment and reference for each message.
                let attachmentParams = Attachment.ConstructionParams.mockStream()
                try attachmentStore.insert(
                    attachmentParams,
                    reference: AttachmentReference.ConstructionParams.mockMessageBodyAttachmentReference(
                        messageRowId: messageRowId!,
                        threadRowId: threadRowId!
                    ),
                    tx: tx
                )
            }
        }

        var (reference1, reference2, reference3) = db.read { tx in
            let reference1 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                tx: tx
            ).first!
            let reference2 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId2)],
                tx: tx
            ).first!
            let reference3 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId3)],
                tx: tx
            ).first!
            return (reference1, reference2, reference3)
        }

        func checkThreadRowId(of reference: AttachmentReference, matches threadId: Int64) {
            switch reference.owner {
            case .message(let messageSource):
                switch messageSource {
                case .bodyAttachment(let metadata):
                    XCTAssertEqual(metadata.threadRowId, threadId)
                case .oversizeText(let metadata):
                    XCTAssertEqual(metadata.threadRowId, threadId)
                case .linkPreview(let metadata):
                    XCTAssertEqual(metadata.threadRowId, threadId)
                case .quotedReply(let metadata):
                    XCTAssertEqual(metadata.threadRowId, threadId)
                case .sticker(let metadata):
                    XCTAssertEqual(metadata.threadRowId, threadId)
                case .contactAvatar(let metadata):
                    XCTAssertEqual(metadata.threadRowId, threadId)
                }
            default:
                XCTFail("Unexpected reference type")
            }
        }

        checkThreadRowId(of: reference1, matches: threadId1)
        checkThreadRowId(of: reference2, matches: threadId1)
        checkThreadRowId(of: reference3, matches: threadId2)

        try db.write { tx in
            // Merge threads
            try attachmentStore.updateMessageAttachmentThreadRowIdsForThreadMerge(
                fromThreadRowId: threadId1,
                intoThreadRowId: threadId3,
                tx: tx
            )
        }

        (reference1, reference2, reference3) = db.read { tx in
            let reference1 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId1)],
                tx: tx
            ).first!
            let reference2 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId2)],
                tx: tx
            ).first!
            let reference3 = attachmentStore.fetchReferences(
                owners: [.messageBodyAttachment(messageRowId: messageId3)],
                tx: tx
            ).first!
            return (reference1, reference2, reference3)
        }

        // The ones that were thread 1 are now thread 3.
        checkThreadRowId(of: reference1, matches: threadId3)
        checkThreadRowId(of: reference2, matches: threadId3)
        checkThreadRowId(of: reference3, matches: threadId2)
    }

    // MARK: - UInt64 Field verification

    func testUInt64RecordFields_Attachment() {
        testUInt64FieldPresence(
            sampleInstance: Attachment.Record(params: Attachment.ConstructionParams.mockPointer()),
            keyPathNames: [
                \.transitUploadTimestamp: "transitUploadTimestamp",
                \.lastTransitDownloadAttemptTimestamp: "lastTransitDownloadAttemptTimestamp",
                \.lastMediaTierDownloadAttemptTimestamp: "lastMediaTierDownloadAttemptTimestamp",
                \.lastThumbnailDownloadAttemptTimestamp: "lastThumbnailDownloadAttemptTimestamp"
            ]
        )
    }

    func testUInt64RecordFields_MessageAttachmentReference() {
        testUInt64FieldPresence(
            sampleInstance: AttachmentReference.MessageAttachmentReferenceRecord(
                ownerType: 1,
                ownerRowId: 1,
                attachmentRowId: 1,
                receivedAtTimestamp: 1,
                contentType: 1,
                renderingFlag: 1,
                idInMessage: nil,
                orderInMessage: nil,
                threadRowId: 1,
                caption: nil,
                sourceFilename: nil,
                sourceUnencryptedByteCount: 1,
                sourceMediaHeightPixels: 1,
                sourceMediaWidthPixels: 1,
                stickerPackId: nil,
                stickerId: 1,
                isViewOnce: false,
                ownerIsPastEditRevision: false
            ),
            keyPathNames: [
                \.receivedAtTimestamp: "receivedAtTimestamp"
            ]
        )
    }

    func testUInt64RecordFields_StoryMessageAttachmentReference() {
        testUInt64FieldPresence(
            sampleInstance: AttachmentReference.StoryMessageAttachmentReferenceRecord(
                ownerType: 1,
                ownerRowId: 1,
                attachmentRowId: 1,
                shouldLoop: false,
                caption: nil,
                captionBodyRanges: nil,
                sourceFilename: nil,
                sourceUnencryptedByteCount: 1,
                sourceMediaHeightPixels: 1,
                sourceMediaWidthPixels: 1
            ),
            keyPathNames: [:]
        )
    }

    func testUInt64RecordFields_ThreadAttachmentReference() {
        testUInt64FieldPresence(
            sampleInstance: AttachmentReference.ThreadAttachmentReferenceRecord(
                ownerRowId: 1,
                attachmentRowId: 1,
                creationTimestamp: 1
            ),
            keyPathNames: [
                \.creationTimestamp: "creationTimestamp"
            ]
        )
    }

    // MARK: - Helpers

    private func insertThreadAndInteraction() -> (threadRowId: Int64, interactionRowId: Int64) {
        return db.write { tx in
            let thread = insertThread(tx: tx)
            let interactionRowId = insertInteraction(thread: thread, tx: tx)
            return (thread.sqliteRowId!, interactionRowId)
        }
    }

    private func insertThread(tx: InMemoryDB.WriteTransaction) -> TSThread {
        let thread = TSThread(uniqueId: UUID().uuidString)
        try! thread.asRecord().insert(tx.db)
        return thread
    }

    private func insertInteraction(thread: TSThread, tx: InMemoryDB.WriteTransaction) -> Int64 {
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try! interaction.asRecord().insert(tx.db)
        return interaction.sqliteRowId!
    }

    private func assertEqual(_ params: Attachment.ConstructionParams, _ attachment: Attachment) {
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        XCTAssertEqual(record, .init(attachment: attachment))
    }

    private func assertEqual(_ params: AttachmentReference.ConstructionParams, _ reference: AttachmentReference) throws {
        switch (params.owner, reference.owner) {
        case (.message, .message(let messageSource)):
            XCTAssertEqual(
                try params.buildRecord(attachmentRowId: reference.attachmentRowId)
                    as! AttachmentReference.MessageAttachmentReferenceRecord,
                AttachmentReference.MessageAttachmentReferenceRecord(attachmentReference: reference, messageSource: messageSource)
            )
        case (.storyMessage, .storyMessage(let storyMessageSource)):
            XCTAssertEqual(
                try params.buildRecord(attachmentRowId: reference.attachmentRowId)
                    as! AttachmentReference.StoryMessageAttachmentReferenceRecord,
                try AttachmentReference.StoryMessageAttachmentReferenceRecord(
                    attachmentReference: reference,
                    storyMessageSource: storyMessageSource
                )
            )
        case (.thread, .thread(let threadSource)):
            XCTAssertEqual(
                try params.buildRecord(attachmentRowId: reference.attachmentRowId)
                    as! AttachmentReference.ThreadAttachmentReferenceRecord,
                AttachmentReference.ThreadAttachmentReferenceRecord(attachmentReference: reference, threadSource: threadSource)
            )
        case (.message, _), (.storyMessage, _), (.thread, _):
            XCTFail("Non matching owner types")
        }
    }

    private func testUInt64FieldPresence<T: UInt64SafeRecord>(
        sampleInstance: T,
        keyPathNames: [PartialKeyPath<T>: String]
    ) {
        var declaredFieldNames = Set<String>()
        for keyPath in T.uint64Fields {
            guard let name = keyPathNames[keyPath] else {
                XCTFail("Unexpected key path!")
                continue
            }
            declaredFieldNames.insert(name)
        }
        for keyPath in T.uint64OptionalFields {
            guard let name = keyPathNames[keyPath] else {
                XCTFail("Unexpected key path!")
                continue
            }
            declaredFieldNames.insert(name)
        }
        for (label, value) in Mirror(reflecting: sampleInstance).children {
            guard
                let label,
                (type(of: value) == UInt64.self) || (type(of: value) == Optional<UInt64>.self)
            else {
                continue
            }
            XCTAssert(declaredFieldNames.contains(label), "Undeclared uint64 field: \(label)")
        }
    }
}
