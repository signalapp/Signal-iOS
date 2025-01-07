//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import XCTest
@testable import SignalServiceKit

class MediaGalleryAttachmentFinderTest: XCTestCase {

    private var db: InMemoryDB!

    override func setUp() async throws {
        db = InMemoryDB()
    }

    // MARK: - Queries

    func testQueryDateRange() throws {
        let (thread, messageRowId) = insertThreadAndInteraction()
        let threadRowId = thread.sqliteRowId!

        // Insert one matching content type before the date range
        try insertAttachment(
            messageRowId: messageRowId,
            threadRowId: threadRowId,
            receivedAtTimestamp: 100,
            contentType: .image,
            orderInOwner: 0
        )
        // ...and one matching content type after the date range
        try insertAttachment(
            messageRowId: messageRowId,
            threadRowId: threadRowId,
            receivedAtTimestamp: 300,
            contentType: .image,
            orderInOwner: 1
        )
        // ...and one non-matching content type within the date range
        try insertAttachment(
            messageRowId: messageRowId,
            threadRowId: threadRowId,
            receivedAtTimestamp: 200,
            contentType: .audio,
            orderInOwner: 2
        )
        // ...and two matching content type within the date range
        try insertAttachment(
            messageRowId: messageRowId,
            threadRowId: threadRowId,
            receivedAtTimestamp: 200,
            contentType: .image,
            orderInOwner: 3
        )
        try insertAttachment(
            messageRowId: messageRowId,
            threadRowId: threadRowId,
            receivedAtTimestamp: 200,
            contentType: .image,
            orderInOwner: 4
        )
        // ...and one within the date range that we will exclude.
        try insertAttachment(
            messageRowId: messageRowId,
            threadRowId: threadRowId,
            receivedAtTimestamp: 200,
            contentType: .image,
            orderInOwner: 5
        )
        // ...and a view once attachment that will be excluded.
        try insertAttachment(
            messageRowId: messageRowId,
            threadRowId: threadRowId,
            receivedAtTimestamp: 200,
            contentType: .image,
            isViewOnce: true,
            orderInOwner: 6
        )
        let exclusionSet = Set<AttachmentReferenceId>([
            .init(ownerId: .messageBodyAttachment(messageRowId: messageRowId), orderInOwner: 5)
        ])

        let finder = MediaGalleryAttachmentFinder(threadId: thread.grdbId!.int64Value, filter: .allPhotoVideoCategory)

        // Should get two results with offset 0
        var query = finder.galleryItemQuery(
            in: .init(
                start: .init(millisecondsSince1970: 150),
                end: .init(millisecondsSince1970: 250)
            ),
            excluding: exclusionSet,
            offset: 0,
            ascending: true
        )

        var results = try db.read { tx in
            return try query.fetchAll(tx.db)
        }

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].receivedAtTimestamp, 200)
        XCTAssertEqual(results[0].orderInMessage, 3)
        XCTAssertEqual(results[1].receivedAtTimestamp, 200)
        XCTAssertEqual(results[1].orderInMessage, 4)

        // Should get just the second result with offset 1
        query = finder.galleryItemQuery(
            in: .init(
                start: .init(millisecondsSince1970: 150),
                end: .init(millisecondsSince1970: 250)
            ),
            excluding: exclusionSet,
            offset: 1,
            ascending: true
        )

        results = try db.read { tx in
            return try query.fetchAll(tx.db)
        }

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].receivedAtTimestamp, 200)
        XCTAssertEqual(results[0].orderInMessage, 4)
    }

    // MARK: - Index Usage

    func testAllQueriesUseIndex() throws {
        let (thread, _) = insertThreadAndInteraction()

        // Set up some parametrized values for tests.
        // Specific values for many things don't matter, just presence
        // and combinations thereof.
        let dateIntervals: [DateInterval?] = [
            nil,
            .init(
                start: .init(millisecondsSince1970: 100),
                end: .init(millisecondsSince1970: 200)
            )
        ]
        let exclusionSets: [Set<AttachmentReferenceId>] = [
            Set(),
            Set([.init(ownerId: .messageBodyAttachment(messageRowId: 100), orderInOwner: nil)]),
            Set([.init(ownerId: .messageBodyAttachment(messageRowId: 200), orderInOwner: 5)]),
            Set([
                .init(ownerId: .messageBodyAttachment(messageRowId: 100), orderInOwner: nil),
                .init(ownerId: .messageBodyAttachment(messageRowId: 200), orderInOwner: nil),
                .init(ownerId: .messageBodyAttachment(messageRowId: 300), orderInOwner: 5)
            ])
        ]
        let offsets: [Int] = [0, 5]
        let limits: [Int] = [5, 100]
        let ascendings: [Bool] = [true, false]

        for filter in AllMediaFilter.allCases {
            if filter == .gifs {
                // Skip gif filter; it uses a b-tree for sorting and doesn't
                // use a simple index.
                continue
            }
            let finder = MediaGalleryAttachmentFinder(threadId: thread.grdbId!.int64Value, filter: filter)
            var queries = [QueryInterfaceRequest<RecordType>]()

            for dateInterval in dateIntervals {
                for exclusionSet in exclusionSets {
                    for offset in offsets {
                        for ascending in ascendings {
                            queries.append(finder.galleryItemQuery(
                                in: dateInterval,
                                excluding: exclusionSet,
                                offset: offset,
                                ascending: ascending
                            ))
                        }
                    }
                }
            }
            for dateInterval in dateIntervals.compacted() {
                for exclusionSet in exclusionSets {
                    for offset in offsets {
                        for limit in limits {
                            queries.append(finder.enumerateMediaAttachmentsQuery(
                                in: dateInterval,
                                excluding: exclusionSet,
                                range: .init(location: offset, length: limit)
                            ))
                        }
                    }
                }
            }
            for dateInterval in dateIntervals {
                for exclusionSet in exclusionSets {
                    for limit in limits {
                        queries.append(finder.enumerateTimestampsQuery(
                            beforeDate: dateInterval?.end,
                            afterDate: nil,
                            excluding: exclusionSet,
                            count: limit,
                            ascending: false
                        ))
                        queries.append(finder.enumerateTimestampsQuery(
                            beforeDate: nil,
                            afterDate: dateInterval?.start,
                            excluding: exclusionSet,
                            count: limit,
                            ascending: true
                        ))
                    }
                }
            }
            for limit in limits {
                queries.append(finder.recentMediaAttachmentsQuery(limit: limit))
            }

            try db.read { tx in
                for query in queries {
                    let preparedStatement = try query.makePreparedRequest(tx.db).statement
                    let queryPlan: [String] = try Row.fetchAll(
                        tx.db,
                        sql: "EXPLAIN QUERY PLAN \(preparedStatement.sql);",
                        arguments: preparedStatement.arguments
                    ).map{ $0["detail"] }

                    // Ensure we use the relevant indexes and...
                    // * we use all the columns up to the ordering columns
                    // * we DONT use expensive B trees for ordering
                    let allowedQueryPlans: [String] = [
                        "SEARCH MessageAttachmentReference USING INDEX message_attachment_reference_media_gallery_single_content_type_index (threadRowId=? AND ownerType=? AND contentType=?",
                        "SEARCH MessageAttachmentReference USING INDEX message_attachment_reference_media_gallery_visualMedia_content_type_index (threadRowId=? AND ownerType=? AND isVisualMediaContentType=?",
                        "SEARCH MessageAttachmentReference USING INDEX message_attachment_reference_media_gallery_fileOrInvalid_content_type_index (threadRowId=? AND ownerType=? AND isInvalidOrFileContentType=?"
                    ]
                    XCTAssert(queryPlan.allSatisfy { queryPlan in
                        for allowedQueryPlan in allowedQueryPlans {
                            if queryPlan.hasPrefix(allowedQueryPlan) {
                                return true
                            }
                        }
                        return false
                    })
                    // There should NOT be expensive B-TREE usage.
                    XCTAssert(queryPlan.allSatisfy { $0.contains("USE TEMP B-TREE").negated })
                }
            }
        }
    }

    // MARK: - Helpers

    typealias RecordType = MediaGalleryAttachmentFinder.RecordType

    private func insertThreadAndInteraction() -> (thread: TSThread, interactionRowId: Int64) {
        let thread = TSThread(uniqueId: UUID().uuidString)
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)

        db.write { tx in
            try! thread.asRecord().insert(tx.db)
            try! interaction.asRecord().insert(tx.db)
        }

        return (thread, interaction.sqliteRowId!)
    }

    @discardableResult
    private func insertAttachment(
        messageRowId: Int64,
        threadRowId: Int64,
        receivedAtTimestamp: UInt64,
        contentType: AttachmentReference.ContentType,
        caption: String? = nil,
        renderingFlag: AttachmentReference.RenderingFlag = .default,
        isViewOnce: Bool = false,
        isPastEditRevision: Bool = false,
        orderInOwner: UInt32,
        idInOwner: UUID? = nil
    ) throws -> Attachment.IDType {
        let attachmentParams = Attachment.ConstructionParams.mockStream()
        let referenceParams = AttachmentReference.ConstructionParams.mock(
            owner: .message(.bodyAttachment(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: receivedAtTimestamp,
                threadRowId: threadRowId,
                contentType: contentType,
                isPastEditRevision: isPastEditRevision,
                caption: caption,
                renderingFlag: renderingFlag,
                orderInOwner: orderInOwner,
                idInOwner: idInOwner,
                isViewOnce: isViewOnce
            )))
        )

        var attachmentRecord = Attachment.Record(params: attachmentParams)
        attachmentRecord.contentType = UInt32(contentType.rawValue)

        try db.write { tx in
            try attachmentRecord.insert(tx.db)
            let referenceRecord = try referenceParams.buildRecord(attachmentRowId: attachmentRecord.sqliteId!)
            try referenceRecord.insert(tx.db)
        }

        return attachmentRecord.sqliteId!
    }
}
