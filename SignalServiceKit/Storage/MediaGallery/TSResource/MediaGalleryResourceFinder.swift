//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wraps MediaGalleryRecordFinder for briging between legacy and v2 attachments.
public struct MediaGalleryResourceFinder {

    private var recordFinder: MediaGalleryRecordFinder
    private var attachmentFinder: MediaGalleryAttachmentFinder

    public var thread: TSThread { recordFinder.thread }
    public var threadId: Int64 { recordFinder.threadId }

    /// Media will be restricted to this type. Otherwise there is no filtering.
    public var filter: AllMediaFilter {
        get { recordFinder.filter }
        set {
            recordFinder.filter = newValue
            attachmentFinder.filter = newValue
        }
    }

    public init(thread: TSThread, filter: AllMediaFilter) {
        self.recordFinder = MediaGalleryRecordFinder(thread: thread, filter: filter)
        self.attachmentFinder = MediaGalleryAttachmentFinder(thread: thread, filter: filter)
    }

    // MARK: -

    public func galleryItemIds(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [MediaGalleryItemId] {
        switch self.mode(tx: tx) {
        case .justV2:
            return attachmentFinder.galleryItemIds(
                in: givenInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                offset: offset,
                ascending: ascending,
                tx: tx
            ).map { .v2($0) }
        case .justLegacy:
            return recordFinder.rowIds(
                in: givenInterval,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                offset: offset,
                ascending: ascending,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map { .legacy(mediaGalleryRecordId: $0) }

        case .bridging:
            let v2Ids = attachmentFinder.galleryItemIds(
                in: givenInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                // No offset for the query.
                offset: 0,
                ascending: ascending,
                tx: tx
            ).map { MediaGalleryItemId.v2($0) }
            let legacyIds = recordFinder.rowIds(
                in: givenInterval,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                // No offset for the query.
                offset: 0,
                ascending: ascending,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map { MediaGalleryItemId.legacy(mediaGalleryRecordId: $0) }

            // Always assume v2 attachments come _after_ legacy attachments.
            // This may not always be correct but...
            // 1. is _mostly_ correct
            // 2. only matters at the boundary where we are migrating legacy to v2
            // 3. is temporary until the migration finishes on this device.
            let orderedArray: [MediaGalleryItemId]
            if ascending {
                orderedArray = legacyIds + v2Ids
            } else {
                orderedArray = v2Ids + legacyIds
            }
            return orderedArray.suffix(max(0, orderedArray.count - offset))
        }
    }

    public func galleryItemIdsAndDates(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [DatedMediaGalleryItemId] {
        switch self.mode(tx: tx) {
        case .justV2:
            return attachmentFinder.galleryItemIdsAndDates(
                in: givenInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                offset: offset,
                ascending: ascending,
                tx: tx
            ).map(\.asItemId)
        case .justLegacy:
            return recordFinder.rowIdsAndDates(
                in: givenInterval,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                offset: offset,
                ascending: ascending,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map(\.asItemId)
        case .bridging:
            let v2ItemIds = attachmentFinder.galleryItemIdsAndDates(
                in: givenInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                // No offset for the query.
                offset: 0,
                ascending: ascending,
                tx: tx
            ).map(\.asItemId)
            let legacyItemIds = recordFinder.rowIdsAndDates(
                in: givenInterval,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                // No offset for the query.
                offset: 0,
                ascending: ascending,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map(\.asItemId)

            let sortedCombinedArray: [DatedMediaGalleryItemId]
            if v2ItemIds.isEmpty {
                sortedCombinedArray = legacyItemIds
            } else if legacyItemIds.isEmpty {
                sortedCombinedArray = v2ItemIds
            } else {
                // Sort across the two in memory.
                // Not ideally efficient, and ALSO not the actually correct sort
                // since there are tiebreaks covered by the SQL queries, but...
                // 1. is _mostly_ correct
                // 2. only matters at the boundary where we are migrating legacy to v2
                // 3. is temporary until the migration finishes on this device.

                // Pre-sort assuming v2 attachments come _after_ legacy attachments.
                let combinedArray: [DatedMediaGalleryItemId]
                if ascending {
                    combinedArray = legacyItemIds + v2ItemIds
                } else {
                    combinedArray = v2ItemIds + legacyItemIds
                }
                sortedCombinedArray = combinedArray.sorted(by: { lhs, rhs in
                    if ascending {
                        return lhs.date < rhs.date
                    } else {
                        return lhs.date > rhs.date
                    }
                })
            }

            return sortedCombinedArray.suffix(max(0, sortedCombinedArray.count - offset))
        }

    }

    public func recentMediaAttachments(limit: Int, tx: DBReadTransaction) -> [ReferencedTSResource] {
        let mode = self.mode(tx: tx)
        var v2Items = [ReferencedTSResource]()
        if mode.useV2 {
            v2Items = attachmentFinder.recentMediaAttachments(
                limit: limit,
                tx: tx
            ).map { $0.referencedTSResource }
        }
        var legacyItems = [ReferencedTSResource]()
        if mode.useLegacy {
            legacyItems = recordFinder.recentMediaAttachments(
                limit: limit,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map {
                ReferencedTSResource(
                    reference: TSAttachmentReference(uniqueId: $0.uniqueId, attachment: $0),
                    attachment: $0
                )
            }
        }

        // Always assume v2 attachments come _after_ legacy attachments.
        // This may not always be correct but...
        // 1. is _mostly_ correct
        // 2. only matters at the boundary where we are migrating legacy to v2
        // 3. is temporary until the migration finishes on this device.
        if v2Items.count == limit {
            return v2Items
        } else {
            return legacyItems.suffix(limit - v2Items.count) + v2Items
        }
    }

    public func enumerateMediaAttachments(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        range: NSRange,
        tx: DBReadTransaction,
        block: (Int, ReferencedTSResource) -> Void
    ) {
        switch self.mode(tx: tx) {
        case .justV2:
            return attachmentFinder.enumerateMediaAttachments(
                in: dateInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                range: range,
                tx: tx,
                block: { index, referencedAttachment in
                    block(index, referencedAttachment.referencedTSResource)
                }
            )
        case .justLegacy:
            return recordFinder.enumerateMediaAttachments(
                in: dateInterval,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                range: range,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                block: { index, tsAttachment in
                    block(
                        index,
                        ReferencedTSResource(
                            reference: TSAttachmentReference(
                                uniqueId: tsAttachment.uniqueId,
                                attachment: tsAttachment
                            ),
                            attachment: tsAttachment
                        )
                    )
                }
            )
        case .bridging:
            // Always assume v2 attachments come _after_ legacy attachments.
            // This may not always be correct but...
            // 1. is _mostly_ correct
            // 2. only matters at the boundary where we are migrating legacy to v2
            // 3. is temporary until the migration finishes on this device.
            var lastLegacyIndex = -1
            recordFinder.enumerateMediaAttachments(
                in: dateInterval,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                range: NSRange(location: 0, length: range.upperBound),
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                block: { (index, tsAttachment) in
                    lastLegacyIndex = index
                    guard index >= range.lowerBound else {
                        return
                    }
                    block(
                        index,
                        ReferencedTSResource(
                            reference: TSAttachmentReference(
                                uniqueId: tsAttachment.uniqueId,
                                attachment: tsAttachment
                            ),
                            attachment: tsAttachment
                        )
                    )
                }
            )
            if lastLegacyIndex >= range.upperBound {
                return
            }
            let v2IndexOffset = lastLegacyIndex + 1
            attachmentFinder.enumerateMediaAttachments(
                in: dateInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                range: NSRange(location: 0, length: range.upperBound - v2IndexOffset),
                tx: tx,
                block: { index, referencedAttachment in
                    let offsetIndex = index + v2IndexOffset
                    guard offsetIndex >= range.lowerBound else {
                        return
                    }
                    block(offsetIndex, referencedAttachment.referencedTSResource)
                }
            )
        }
    }

    public typealias EnumerationCompletion = MediaGalleryAttachmentFinder.EnumerationCompletion

    public func enumerateTimestamps(
        before date: Date,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryItemId) -> Void
    ) -> EnumerationCompletion {
        switch self.mode(tx: tx) {
        case .justV2:
            return attachmentFinder.enumerateTimestamps(
                before: date,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                count: count,
                tx: tx,
                block: { datedId in
                    block(datedId.asItemId)
                }
            )
        case .justLegacy:
            return recordFinder.enumerateTimestamps(
                before: date,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                count: count,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                block: { datedId in
                    block(datedId.asItemId)
                }
            )
        case .bridging:
            // Always assume v2 attachments come _after_ legacy attachments.
            // This may not always be correct but...
            // 1. is _mostly_ correct
            // 2. only matters at the boundary where we are migrating legacy to v2
            // 3. is temporary until the migration finishes on this device.
            var v2Count = 0
            let v2Result = attachmentFinder.enumerateTimestamps(
                before: date,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                count: count,
                tx: tx,
                block: { datedId in
                    v2Count += 1
                    block(datedId.asItemId)
                }
            )
            switch v2Result {
            case .finished:
                return .finished
            case .reachedEnd:
                return recordFinder.enumerateTimestamps(
                    before: date,
                    excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                    count: count - v2Count,
                    transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                    block: { datedId in
                        block(datedId.asItemId)
                    }
                )
            }
        }
    }

    public func enumerateTimestamps(
        after date: Date,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryItemId) -> Void
    ) -> EnumerationCompletion {
        switch self.mode(tx: tx) {
        case .justV2:
            return attachmentFinder.enumerateTimestamps(
                after: date,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                count: count,
                tx: tx,
                block: { datedId in
                    block(datedId.asItemId)
                }
            )
        case .justLegacy:
            return recordFinder.enumerateTimestamps(
                after: date,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                count: count,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                block: { datedId in
                    block(datedId.asItemId)
                }
            )
        case .bridging:
            // Always assume v2 attachments come _after_ legacy attachments.
            // This may not always be correct but...
            // 1. is _mostly_ correct
            // 2. only matters at the boundary where we are migrating legacy to v2
            // 3. is temporary until the migration finishes on this device.
            var legacyCount = 0
            let legacyResult = recordFinder.enumerateTimestamps(
                after: date,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                count: count,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                block: { datedId in
                    legacyCount += 1
                    block(datedId.asItemId)
                }
            )
            switch legacyResult {
            case .finished:
                return .finished
            case .reachedEnd:
                return attachmentFinder.enumerateTimestamps(
                    after: date,
                    excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                    count: count - legacyCount,
                    tx: tx,
                    block: { datedId in
                        block(datedId.asItemId)
                    }
                )
            }
        }
    }

    // Disregards filter.
    public func galleryItemId(
        of attachment: ReferencedTSResourceStream,
        in interval: DateInterval,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        tx: DBReadTransaction
    ) -> MediaGalleryItemId? {
        switch (attachment.attachmentStream.concreteStreamType, attachment.reference.concreteType) {
        case let (.v2(attachmentStream), .v2(reference)):
            return attachmentFinder.galleryItemId(
                of: .init(reference: reference, attachmentStream: attachmentStream),
                in: interval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                tx: tx
            ).map { .v2($0) }
        case (.legacy(let tsAttachment), .legacy):
            return recordFinder.rowid(
                of: tsAttachment,
                in: interval,
                excluding: bridgeLegacyAttachmentIds(deletedAttachmentIds),
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map { .legacy(mediaGalleryRecordId: $0) }

        case (.v2, .legacy), (.legacy, .v2):
            owsFailDebug("Invalid combination")
            return nil
        }
    }

    /// Returns the number of attachments attached to `interaction`, whether or not they are media attachments. Disregards allowedMediaType.
    public func countAllAttachments(
        of interaction: TSInteraction,
        tx: DBReadTransaction
    ) throws -> UInt {
        let mode = self.mode(tx: tx)
        var count: UInt = 0
        if mode.useV2 {
            count += try attachmentFinder.countAllAttachments(
                of: interaction,
                tx: tx
            )
        }
        if mode.useLegacy {
            count += try recordFinder.countAllAttachments(
                of: interaction,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            )
        }
        return count
    }

    public func isEmptyOfAttachments(
        interaction: TSInteraction,
        tx: DBReadTransaction
    ) throws -> Bool {
        return try countAllAttachments(of: interaction, tx: tx) == 0
    }

    // MARK: - Helpers

    private func bridgeLegacyAttachmentIds(
        _ attachmentIds: Set<MediaGalleryResourceId>
    ) -> Set<String> {
        var finalIds = Set<String>()
        attachmentIds.forEach {
            switch $0 {
            case .legacy(let attachmentUniqueId):
                finalIds.insert(attachmentUniqueId)
            case .v2:
                break
            }
        }
        return finalIds
    }

    private func bridgeV2AttachmentIds(
        _ attachmentIds: Set<MediaGalleryResourceId>
    ) -> Set<AttachmentReferenceId> {
        var finalIds = Set<AttachmentReferenceId>()
        attachmentIds.forEach {
            switch $0 {
            case .legacy:
                break
            case .v2(let id):
                finalIds.insert(id)
            }
        }
        return finalIds
    }

    private enum Mode {
        /// We should exclusively use legacy MediaGalleryRecordFinder.
        /// True when v2 attachments have not been enabled at all.
        case justLegacy
        /// We should use both legacy MediaGalleryRecordFinder and v2 MediaGalleryAttachmentFinder.
        /// True when v2 attachments have been enabled but have not finished migrating.
        case bridging
        /// We should exclusively use v2 MediaGalleryAttachmentFinder.
        /// True once v2 attachments have been enabled and finished migrating.
        case justV2

        var useLegacy: Bool {
            switch self {
            case .justLegacy, .bridging:
                return true
            case .justV2:
                return false
            }
        }

        var useV2: Bool {
            switch self {
            case .justLegacy:
                return false
            case .bridging, .justV2:
                return true
            }
        }
    }

    private func mode(tx: DBReadTransaction) -> Mode {
        if
            DependenciesBridge.shared.tsResourceManager
                .didFinishTSAttachmentToAttachmentMigration(tx: tx)
        {
            return .justV2
        }
        return .bridging
    }
}
