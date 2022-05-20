// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalUtilitiesKit

public class MediaGalleryViewModel: TransactionObserver {
    public let threadId: String
    public let threadVariant: SessionThread.Variant
    private var focusedAttachmentId: String?
    public private(set) var focusedIndexPath: IndexPath?
    
    /// This value is the current state of an album view
    private var cachedInteractionIdBefore: Atomic<[Int64: Int64]> = Atomic([:])
    private var cachedInteractionIdAfter: Atomic<[Int64: Int64]> = Atomic([:])
    
    public var interactionIdBefore: [Int64: Int64] { cachedInteractionIdBefore.wrappedValue }
    public var interactionIdAfter: [Int64: Int64] { cachedInteractionIdAfter.wrappedValue }
    public private(set) var albumData: [Int64: [Item]] = [:]
    
    /// This value is the current state of a gallery view
    public private(set) var galleryData: [SectionModel] = []

    // MARK: - Paging
    
    public struct PageInfo {
        public enum Target: Equatable {
            case before
            case around(id: String)
            case after
        }
        
        let pageSize: Int
        let pageOffset: Int
        let currentCount: Int
        let totalCount: Int
        
        // MARK: - Initizliation
        
        init(
            pageSize: Int,
            pageOffset: Int = 0,
            currentCount: Int = 0,
            totalCount: Int = 0
        ) {
            self.pageSize = pageSize
            self.pageOffset = pageOffset
            self.currentCount = currentCount
            self.totalCount = totalCount
        }
    }
    
    private var isFetchingMoreItems: Atomic<Bool> = Atomic(false)
    private var pageInfo: Atomic<PageInfo>
    
    // Gallery observing
    
    private let updatedRows: Atomic<Set<TrackedChange>> = Atomic([])
    public var onGalleryChange: (([SectionModel], PageInfo) -> ())?
    
    // MARK: - Initialization
    
    init(
        threadId: String,
        threadVariant: SessionThread.Variant,
        pageSize: Int = 1,
        focusedAttachmentId: String? = nil
    ) {
        self.threadId = threadId
        self.threadVariant = threadVariant
        self.pageInfo = Atomic(PageInfo(pageSize: pageSize))
        self.focusedAttachmentId = focusedAttachmentId
    }
    
    // MARK: - Data
    
    public struct GalleryDate: Differentiable, Equatable, Comparable, Hashable {
        private static let thisYearFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"

            return formatter
        }()

        private static let olderFormatter: DateFormatter = {
            // FIXME: localize for RTL, or is there a built in way to do this?
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"

            return formatter
        }()
        
        let year: Int
        let month: Int
        
        private var date: Date? {
            var components = DateComponents()
            components.month = self.month
            components.year = self.year

            return Calendar.current.date(from: components)
        }

        var localizedString: String {
            let isSameMonth: Bool = (self.month == Calendar.current.component(.month, from: Date()))
            let isCurrentYear: Bool = (self.year == Calendar.current.component(.year, from: Date()))
            let galleryDate: Date = (self.date ?? Date())
            
            switch (isSameMonth, isCurrentYear) {
                case (true, true): return "MEDIA_GALLERY_THIS_MONTH_HEADER".localized()
                case (false, true): return GalleryDate.thisYearFormatter.string(from: galleryDate)
                default: return GalleryDate.olderFormatter.string(from: galleryDate)
            }
        }
        
        // MARK: - --Initialization

        init(messageDate: Date) {
            self.year = Calendar.current.component(.year, from: messageDate)
            self.month = Calendar.current.component(.month, from: messageDate)
        }

        // MARK: - --Comparable

        public static func < (lhs: GalleryDate, rhs: GalleryDate) -> Bool {
            switch ((lhs.year != rhs.year), (lhs.month != rhs.month)) {
                case (true, _): return lhs.year < rhs.year
                case (_, true): return lhs.month < rhs.month
                default: return false
            }
        }
    }
    
    public typealias SectionModel = ArraySection<Section, Item>
    
    public enum Section: Differentiable, Equatable, Comparable, Hashable {
        case emptyGallery
        case loadNewer
        case galleryMonth(date: GalleryDate)
        case loadOlder
    }
    
    public struct Item: FetchableRecord, Decodable, Differentiable, Equatable, Hashable, Comparable {
        fileprivate static let interactionIdKey: String = CodingKeys.interactionId.stringValue
        fileprivate static let interactionVariantKey: String = CodingKeys.interactionVariant.stringValue
        fileprivate static let interactionAuthorIdKey: String = CodingKeys.interactionAuthorId.stringValue
        fileprivate static let interactionTimestampMsKey: String = CodingKeys.interactionTimestampMs.stringValue
        fileprivate static let attachmentRowIdKey: String = CodingKeys.attachmentRowId.stringValue
        fileprivate static let attachmentAlbumIndexKey: String = CodingKeys.attachmentAlbumIndex.stringValue
        
        public var differenceIdentifier: String {
            return attachment.id
        }
        
        let interactionId: Int64
        let interactionVariant: Interaction.Variant
        let interactionAuthorId: String
        let interactionTimestampMs: Int64
        
        let attachmentRowId: Int64
        let attachmentAlbumIndex: Int
        let attachment: Attachment
        
        var galleryDate: GalleryDate {
            GalleryDate(
                messageDate: Date(timeIntervalSince1970: (Double(interactionTimestampMs) / 1000))
            )
        }
        
        var isVideo: Bool { attachment.isVideo }
        var isAnimated: Bool { attachment.isAnimated }
        var isImage: Bool { attachment.isImage }

        var imageSize: CGSize {
            guard let width: UInt = attachment.width, let height: UInt = attachment.height else {
                return .zero
            }
            
            return CGSize(width: Int(width), height: Int(height))
        }
        
        var captionForDisplay: String? { attachment.caption?.filterForDisplay }
        
        // MARK: - Comparable
        
        public static func < (lhs: Item, rhs: Item) -> Bool {
            if lhs.interactionTimestampMs == rhs.interactionTimestampMs {
                return (lhs.attachmentAlbumIndex < rhs.attachmentAlbumIndex)
            }
            
            return (lhs.interactionTimestampMs < rhs.interactionTimestampMs)
        }
        
        // MARK: - Query
        
        private static let baseQueryFilterSQL: SQL = {
            let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
            
            return SQL("\(attachment[.isVisualMedia]) = true AND \(attachment[.isValid]) = true")
        }()
        
        private static let galleryQueryOrderSQL: SQL = {
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            /// **Note:** This **MUST** match the desired sort behaviour for the screen otherwise paging will be
            /// very broken
            return SQL("\(interaction[.timestampMs].desc), \(interactionAttachment[.albumIndex])")
        }()
        
        /// Retrieve the index that the attachment with the given `attachmentId` will have in the gallery
        fileprivate static func galleryIndex(for attachmentId: String) -> SQLRequest<Int> {
            let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            return """
                SELECT
                    (gallery.galleryIndex - 1) AS galleryIndex -- Converting from 1-Indexed to 0-indexed
                FROM (
                    SELECT
                        \(attachment[.id]) AS id,
                        ROW_NUMBER() OVER (ORDER BY \(galleryQueryOrderSQL)) AS galleryIndex
                    FROM \(Attachment.self)
                    JOIN \(InteractionAttachment.self) ON \(interactionAttachment[.attachmentId]) = \(attachment[.id])
                    JOIN \(Interaction.self) ON \(interaction[.id]) = \(interactionAttachment[.interactionId])
                    WHERE \(baseQueryFilterSQL)
                ) AS gallery
                WHERE \(SQL("gallery.id = \(attachmentId)"))
            """
        }
        
        /// Retrieve the indexes the given attachment row will have in the gallery
        fileprivate static func galleryIndexes(for rowIds: Set<Int64>, threadId: String) -> SQLRequest<Int> {
            let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            return """
                SELECT
                    (gallery.galleryIndex - 1) AS galleryIndex -- Converting from 1-Indexed to 0-indexed
                FROM (
                    SELECT
                        \(attachment.alias[Column.rowID]) AS rowid,
                        ROW_NUMBER() OVER (ORDER BY \(galleryQueryOrderSQL)) AS galleryIndex
                    FROM \(Attachment.self)
                    JOIN \(InteractionAttachment.self) ON \(interactionAttachment[.attachmentId]) = \(attachment[.id])
                    JOIN \(Interaction.self) ON (
                        \(interaction[.id]) = \(interactionAttachment[.interactionId]) AND
                        \(SQL("\(interaction[.threadId]) = \(threadId)"))
                    )
                    WHERE \(baseQueryFilterSQL)
                ) AS gallery
                WHERE \(SQL("gallery.rowid IN \(rowIds)"))
            """
        }
        
        private static let baseQuery: QueryInterfaceRequest<Item> = {
            let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            return Attachment
                .select(
                    interaction[.id].forKey(Item.interactionIdKey),
                    interaction[.variant].forKey(Item.interactionVariantKey),
                    interaction[.authorId].forKey(Item.interactionAuthorIdKey),
                    interaction[.timestampMs].forKey(Item.interactionTimestampMsKey),
                    
                    attachment.alias[Column.rowID].forKey(Item.attachmentRowIdKey),
                    interactionAttachment[.albumIndex].forKey(Item.attachmentAlbumIndexKey),
                    attachment.allColumns()
                )
                .aliased(attachment)
                .filter(literal: baseQueryFilterSQL)
                .joining(
                    required: Attachment.interactionAttachments
                        .aliased(interactionAttachment)
                        .joining(
                            required: InteractionAttachment.interaction
                                .aliased(interaction)
                        )
                )
                .asRequest(of: Item.self)
        }()
        
        fileprivate static let albumQuery: QueryInterfaceRequest<Item> = {
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            return Item.baseQuery.order(interactionAttachment[.albumIndex])
        }()
        
        fileprivate static let galleryQuery: QueryInterfaceRequest<Item> = {
            return Item.baseQuery
                .order(literal: galleryQueryOrderSQL)
        }()
        
        fileprivate static let galleryQueryReversed: QueryInterfaceRequest<Item> = {
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            /// **Note:** This **MUST** always result in the same data as `galleryQuery` but in the opposite order
            return Item.baseQuery
                .order(interaction[.timestampMs], interactionAttachment[.albumIndex].desc)
        }()

        func thumbnailImage(async: @escaping (UIImage) -> ()) {
            attachment.thumbnail(size: .small, success: { image, _ in async(image) }, failure: {})
        }
    }
    
    // MARK: - Album
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** The 'trackingConstantRegion' is optimised in such a way that the request needs to be static
    /// otherwise there may be situations where it doesn't get updates, this means we can't have conditional queries
    public typealias AlbumObservation = ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<[Item]>>>
    public lazy var observableAlbumData: AlbumObservation = buildAlbumObservation(for: nil)
    
    private func buildAlbumObservation(for interactionId: Int64?) -> AlbumObservation {
        return ValueObservation
            .trackingConstantRegion { db -> [Item] in
                guard let interactionId: Int64 = interactionId else { return [] }
                
                let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                
                return try Item.albumQuery
                    .filter(interaction[.id] == interactionId)
                    .fetchAll(db)
            }
            .removeDuplicates()
    }
    
    
    // MARK: - Gallery
    
    /// This function is used to load a gallery page using the provided `limitInfo`, if a `focusedAttachmentId` is provided then
    /// the `limitInfo.offset` value will be ignored and it will retrieve `limitInfo.limit` values positioning the focussed item
    /// as closed to the middle as possible prioritising retrieving `limitInfo.limit` items total
    ///
    /// **Note:** The `focusedAttachmentId` should only be provided during the first call, subsequent calls should solely provide
    /// the `limitInfo` so content can be added before and after the initial page
    private func loadGalleryPage(
        _ target: PageInfo.Target,
        currentPageInfo: PageInfo
    ) -> (items: [Item], updatedPageInfo: PageInfo) {
        return GRDBStorage.shared
            .read { db in
                let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                let totalCount: Int = try Item.galleryQuery
                    .filter(interaction[.threadId] == threadId)
                    .fetchCount(db)
                let queryOffset: Int = {
                    switch target {
                        case .before:
                            return max(0, (currentPageInfo.pageOffset - currentPageInfo.pageSize))
                            
                        case .around(let targetId):
                            // If we want to focus on a specific item then we need to find it's index in
                            // the queried data
                            guard let targetIndex: Int = try? Int.fetchOne(db, Item.galleryIndex(for: targetId)) else {
                                // If we couldn't find the targetId then just load the page after the current one
                                return (currentPageInfo.pageOffset + currentPageInfo.pageSize)
                            }
                            
                            // If the focused item is within the first half of the page then we still want
                            // to retrieve a full page so calculate the offset needed to do so
                            let halfPageSize: Int = Int(floor(Double(currentPageInfo.pageSize) / 2))
                            
                            // If the focused item is within the first or last half page then just
                            // start from the start/end of the content
                            guard targetIndex > halfPageSize else { return 0 }
                            guard targetIndex < (totalCount - halfPageSize) else {
                                return (totalCount - currentPageInfo.pageSize)
                            }
                            
                            return (targetIndex - halfPageSize)
                            
                        case .after:
                            return (currentPageInfo.pageOffset + currentPageInfo.currentCount)
                    }
                }()
                
                let items: [Item] = try Item.galleryQuery
                    .filter(interaction[.threadId] == threadId)
                    .limit(currentPageInfo.pageSize, offset: queryOffset)
                    .fetchAll(db)
                let updatedLimitInfo: PageInfo = PageInfo(
                    pageSize: currentPageInfo.pageSize,
                    pageOffset: (target != .after ?
                        queryOffset :
                        currentPageInfo.pageOffset
                    ),
                    currentCount: (currentPageInfo.currentCount + items.count),
                    totalCount: totalCount
                )
                
                return (items, updatedLimitInfo)
            }
            .defaulting(to: ([], currentPageInfo))
    }
    
    private func addingSystemSections(to data: [SectionModel], for pageInfo: PageInfo) -> [SectionModel] {
        // Remove and re-add the custom sections as needed
        return [
            (data.isEmpty ? [SectionModel(section: .emptyGallery)] : []),
            (!data.isEmpty && pageInfo.pageOffset > 0 ? [SectionModel(section: .loadNewer)] : []),
            data.filter { section -> Bool in
                switch section.model {
                    case .galleryMonth: return true
                    case .emptyGallery, .loadOlder, .loadNewer: return false
                }
            },
            (!data.isEmpty && (pageInfo.pageOffset + pageInfo.currentCount) < pageInfo.totalCount ?
                [SectionModel(section: .loadOlder)] :
                []
            )
        ]
        .flatMap { $0 }
    }
    
    private func updatedGalleryData(
        with existingData: [SectionModel],
        dataToUpsert: [Item],
        pageInfoToUpdate: PageInfo
    ) -> (sections: [SectionModel], pageInfo: PageInfo) {
        guard !dataToUpsert.isEmpty else { return (existingData, pageInfoToUpdate) }
        
        let updatedGalleryData: (sections: [SectionModel], pageInfo: PageInfo) = updatedGalleryData(
            with: self.galleryData,
            dataToUpsert: (dataToUpsert, pageInfoToUpdate)
        )
        let existingDataCount: Int = existingData
            .map { $0.elements.count }
            .reduce(0, +)
        let updatedGalleryDataCount: Int = updatedGalleryData.sections
            .map { $0.elements.count }
            .reduce(0, +)
        let gallerySizeDiff: Int = (updatedGalleryDataCount - existingDataCount)
        let updatedPageInfo: PageInfo = PageInfo(
            pageSize: pageInfoToUpdate.pageSize,
            pageOffset: pageInfoToUpdate.pageOffset,
            currentCount: (pageInfoToUpdate.currentCount + gallerySizeDiff),
            totalCount: (pageInfoToUpdate.totalCount + gallerySizeDiff)
        )
        
        // Add the "system" sections, sort the sections and return the result
        return (
            self.addingSystemSections(to: updatedGalleryData.sections, for: updatedPageInfo)
                .sorted { lhs, rhs -> Bool in (lhs.model > rhs.model) },
            updatedPageInfo
        )
    }
    
    private func updatedGalleryData(
        with existingData: [SectionModel],
        dataToUpsert: (items: [Item], updatedPageInfo: PageInfo)
    ) -> (sections: [SectionModel], pageInfo: PageInfo) {
        var updatedGalleryData: [SectionModel] = existingData
        
        dataToUpsert
            .items
            .grouped(by: \.galleryDate)
            .forEach { key, items in
                guard let existingIndex = galleryData.firstIndex(where: { $0.model == .galleryMonth(date: key) }) else {
                    // Insert a new section
                    updatedGalleryData.append(
                        ArraySection(
                            model: .galleryMonth(date: key),
                            elements: items
                                .sorted()
                                .reversed()
                        )
                    )
                    return
                }
                
                // Filter out collisions, replacing them with the updated values and insert
                // and new values
                let itemRowIds: Set<Int64> = items.map { $0.attachmentRowId }.asSet()
                
                updatedGalleryData[existingIndex] = ArraySection(
                    model: .galleryMonth(date: key),
                    elements: updatedGalleryData[existingIndex].elements
                        .filter { !itemRowIds.contains($0.attachmentRowId) }
                        .appending(contentsOf: items)
                        .sorted()
                        .reversed()
                )
            }
        
        // Add the "system" sections, sort the sections and return the result
        return (
            self.addingSystemSections(to: updatedGalleryData, for: dataToUpsert.updatedPageInfo)
                .sorted { lhs, rhs -> Bool in (lhs.model > rhs.model) },
            dataToUpsert.updatedPageInfo
        )
    }
    
    // MARK: - TransactionObserver
    
    private struct TrackedChange: Equatable, Hashable {
        let kind: DatabaseEvent.Kind
        let rowId: Int64
    }
    
    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        switch eventKind {
            case .delete(let tableName): return (tableName == Attachment.databaseTableName)
            case .update(let tableName, let columnNames):
                /// **Warning:** This filtering allows us to ignore all changes to attachments except
                /// for the 'isValid' column, unfortunately calling the `with()` function on an attachment
                /// does result in this column being seen as updated (even if the value doesn't change) so
                /// we need to be careful where we set it to avoid unnecessarily triggering updates
                return (
                    tableName == Attachment.databaseTableName &&
                    columnNames.contains(Attachment.Columns.isValid.name)
                )
            
            // We can ignore 'insert' events as we only care about valid attachments
            case .insert: return false
        }
    }
    
    public func databaseDidChange(with event: DatabaseEvent) {
        // This will get called for whenever an Attachment's 'isValid' column is
        // updated (ie. an attachment finished uploading/downloading), unfortunately
        // we won't know if the attachment is actually relevant yet as it could be for
        // another thread or it might not be a media attachment
        let trackedChange: TrackedChange = TrackedChange(
            kind: event.kind,
            rowId: event.rowID
        )
        updatedRows.mutate { $0.insert(trackedChange) }
    }
    
    // Note: We will process all updates which come through this method even if
    // 'onGalleryChange' is null because if the UI stops observing and then starts again
    // later we don't want them to have missed out on changes which happened while they
    // weren't subscribed (and doing a full re-query seems painful...)
    public func databaseDidCommit(_ db: Database) {
        var committedUpdatedRows: Set<TrackedChange> = []
        self.updatedRows.mutate { updatedRows in
            committedUpdatedRows = updatedRows
            updatedRows.removeAll()
        }
        
        // Note: This method will be called regardless of whether there were actually changes
        // in the areas we are observing so we want to early-out if there aren't any relevant
        // updated rows
        guard !committedUpdatedRows.isEmpty else { return }
        
        var updatedPageInfo: PageInfo = self.pageInfo.wrappedValue
        let attachmentRowIdsToQuery: Set<Int64> = committedUpdatedRows
            .filter { $0.kind != .delete }
            .map { $0.rowId }
            .asSet()
        let attachmentRowIdsToDelete: Set<Int64> = committedUpdatedRows
            .filter { $0.kind == .delete }
            .map { $0.rowId }
            .asSet()
        let oldGalleryDataCount: Int = self.galleryData
            .map { $0.elements.count }
            .reduce(0, +)
        var galleryDataWithDeletions: [SectionModel] = self.galleryData
        
        // First remove any items which have been deleted
        if !attachmentRowIdsToDelete.isEmpty {
            galleryDataWithDeletions = galleryDataWithDeletions
                .map { section -> SectionModel in
                    ArraySection(
                        model: section.model,
                        elements: section.elements
                            .filter { item -> Bool in !attachmentRowIdsToDelete.contains(item.attachmentRowId) }
                    )
                }
                .filter { section -> Bool in !section.elements.isEmpty }
            let updatedGalleryDataCount: Int = galleryDataWithDeletions
                .map { $0.elements.count }
                .reduce(0, +)
            
            // Make sure there were actually changes
            if updatedGalleryDataCount != oldGalleryDataCount {
                let gallerySizeDiff: Int = (updatedGalleryDataCount - oldGalleryDataCount)
                
                updatedPageInfo = PageInfo(
                    pageSize: updatedPageInfo.pageSize,
                    pageOffset: updatedPageInfo.pageOffset,
                    currentCount: (updatedPageInfo.currentCount + gallerySizeDiff),
                    totalCount: (updatedPageInfo.totalCount + gallerySizeDiff)
                )
            }
        }
        
        /// Store the 'deletions-only' update logic in a block as there are a number of places we will fallback to this logic
        let sendDeletionsOnlyUpdateIfNeeded: () -> () = {
            guard !attachmentRowIdsToDelete.isEmpty else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.onGalleryChange?(galleryDataWithDeletions, updatedPageInfo)
            }
        }
        
        // If there are no inserted/updated rows then trigger the update callback and stop here
        guard !attachmentRowIdsToQuery.isEmpty else {
            sendDeletionsOnlyUpdateIfNeeded()
            return
        }
        
        // Fetch the indexes of the rowIds so we can determine whether they should be added to the screen
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        let itemIndexes: [Int] = (try? Item.galleryIndexes(for: attachmentRowIdsToQuery, threadId: self.threadId)
            .fetchAll(db))
            .defaulting(to: [])
        
        // Determine if the indexes for the row ids should be displayed on the screen and remove any
        // which shouldn't - values less than 'currentCount' or if there is at least one value less than
        // 'currentCount' and the indexes are sequential (ie. more than the current loaded content was
        // added at once)
        let itemsAreSequential: Bool = (itemIndexes.map { $0 - 1 }.dropFirst() == itemIndexes.dropLast())
        let validAttachmentRowIds: Set<Int64> = (itemsAreSequential && itemIndexes.contains(where: { $0 < updatedPageInfo.currentCount }) ?
            attachmentRowIdsToQuery :
            zip(itemIndexes, attachmentRowIdsToQuery)
                .filter { index, _ -> Bool in index < updatedPageInfo.currentCount }
                .map { _, rowId -> Int64 in rowId }
                .asSet()
        )
        
        // If there are no valid attachment row ids then stop here
        guard !validAttachmentRowIds.isEmpty else {
            sendDeletionsOnlyUpdateIfNeeded()
            return
        }
        
        // Fetch the inserted/updated rows
        let updatedItems: [Item] = (try? Item.galleryQuery
            .filter(validAttachmentRowIds.contains(Column.rowID))
            .filter(interaction[.threadId] == self.threadId)
            .fetchAll(db))
            .defaulting(to: [])

        // If the inserted/updated rows we irrelevant (eg. associated to another thread, a quote or a link
        // preview) then trigger the update callback (if there were deletions) and stop here
        guard !updatedItems.isEmpty else {
            sendDeletionsOnlyUpdateIfNeeded()
            return
        }
        
        // Process the upserted data
        let updatedGalleryData: (sections: [SectionModel], pageInfo: PageInfo) = updatedGalleryData(
            with: galleryDataWithDeletions,
            dataToUpsert: updatedItems,
            pageInfoToUpdate: updatedPageInfo
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.onGalleryChange?(updatedGalleryData.sections, updatedGalleryData.pageInfo)
        }
    }
    
    public func databaseDidRollback(_ db: Database) {}
    
    // MARK: - Functions
    
    @discardableResult public func loadAndCacheAlbumData(for interactionId: Int64) -> [Item] {
        typealias AlbumInfo = (albumData: [Item], interactionIdBefore: Int64?, interactionIdAfter: Int64?)
        
        // Note: It's possible we already have cached album data for this interaction
        // but to avoid displaying stale data we re-fetch from the database anyway
        let maybeAlbumInfo: AlbumInfo? = GRDBStorage.shared
            .read { db -> AlbumInfo in
                let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                let newAlbumData: [Item] = try Item.albumQuery
                    .filter(interaction[.id] == interactionId)
                    .fetchAll(db)
                
                guard let albumTimestampMs: Int64 = newAlbumData.first?.interactionTimestampMs else {
                    return (newAlbumData, nil, nil)
                }
                
                let itemBefore: Item? = try Item.galleryQueryReversed
                    .filter(interaction[.timestampMs] > albumTimestampMs)
                    .fetchOne(db)
                let itemAfter: Item? = try Item.galleryQuery
                    .filter(interaction[.timestampMs] < albumTimestampMs)
                    .fetchOne(db)
                
                return (newAlbumData, itemBefore?.interactionId, itemAfter?.interactionId)
            }
        
        guard let newAlbumInfo: AlbumInfo = maybeAlbumInfo else { return [] }
        
        // Cache the album info for the new interactionId
        self.updateAlbumData(newAlbumInfo.albumData, for: interactionId)
        self.cachedInteractionIdBefore.mutate { $0[interactionId] = newAlbumInfo.interactionIdBefore }
        self.cachedInteractionIdAfter.mutate { $0[interactionId] = newAlbumInfo.interactionIdAfter }
        
        return newAlbumInfo.albumData
    }
    
    public func replaceAlbumObservation(toObservationFor interactionId: Int64) {
        self.observableAlbumData = self.buildAlbumObservation(for: interactionId)
    }
    
    public func updateAlbumData(_ updatedData: [Item], for interactionId: Int64) {
        self.albumData[interactionId] = updatedData
    }
    
    public func updateGalleryData(_ updatedData: [SectionModel], pageInfo: PageInfo) {
        self.galleryData = updatedData
        self.pageInfo.mutate { $0 = pageInfo }
        
        // If we have a focused attachment id then we need to make sure the 'focusedIndexPath'
        // is updated to be accurate
        if let focusedAttachmentId: String = focusedAttachmentId {
            self.focusedIndexPath = nil
            
            for (section, sectionData) in updatedData.enumerated() {
                for (index, item) in sectionData.elements.enumerated() {
                    if item.attachment.id == focusedAttachmentId {
                        self.focusedIndexPath = IndexPath(item: index, section: section)
                        break
                    }
                }
                
                if self.focusedIndexPath != nil { break }
            }
        }
    }
    
    public func loadNewerGalleryItems() {
        // Only allow on 'load older' fetch at a time
        guard !isFetchingMoreItems.wrappedValue else { return }
        
        // Prevent more fetching until we have completed adding the page
        isFetchingMoreItems.mutate { $0 = true }
        
        // Load the page before the current data (newer items) then merge and sort
        // with the current data
        let updatedGalleryData: (sections: [SectionModel], pageInfo: PageInfo) = updatedGalleryData(
            with: galleryData,
            dataToUpsert: loadGalleryPage(
                .before,
                currentPageInfo: pageInfo.wrappedValue
            )
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.onGalleryChange?(updatedGalleryData.sections, updatedGalleryData.pageInfo)
            self?.isFetchingMoreItems.mutate { $0 = false }
        }
    }
    
    public func loadOlderGalleryItems() {
        // Only allow on 'load older' fetch at a time
        guard !isFetchingMoreItems.wrappedValue else { return }
        
        // Prevent more fetching until we have completed adding the page
        isFetchingMoreItems.mutate { $0 = true }
        
        // Load the page after the current data (older items) then merge and sort
        // with the current data
        let updatedGalleryData: (sections: [SectionModel], pageInfo: PageInfo) = updatedGalleryData(
            with: galleryData,
            dataToUpsert: loadGalleryPage(
                .after,
                currentPageInfo: pageInfo.wrappedValue
            )
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.onGalleryChange?(updatedGalleryData.sections, updatedGalleryData.pageInfo)
            self?.isFetchingMoreItems.mutate { $0 = false }
        }
    }
    
    public func updateFocusedItem(attachmentId: String, indexPath: IndexPath) {
        // Note: We need to set both of these as the 'focusedIndexPath' is usually
        // derived and if the data changes it will be regenerated using the
        // 'focusedAttachmentId' value
        self.focusedAttachmentId = attachmentId
        self.focusedIndexPath = indexPath
    }
    
    // MARK: - Creation Functions
    
    public static func createDetailViewController(
        for threadId: String,
        threadVariant: SessionThread.Variant,
        interactionId: Int64,
        selectedAttachmentId: String,
        options: [MediaGalleryOption]
    ) -> UIViewController? {
        // Load the data for the album immediately (needed before pushing to the screen so
        // transitions work nicely)
        let viewModel: MediaGalleryViewModel = MediaGalleryViewModel(
            threadId: threadId,
            threadVariant: threadVariant
        )
        viewModel.loadAndCacheAlbumData(for: interactionId)
        viewModel.replaceAlbumObservation(toObservationFor: interactionId)
        
        guard
            !viewModel.albumData.isEmpty,
            let initialItem: Item = viewModel.albumData[interactionId]?.first(where: { item -> Bool in
                item.attachment.id == selectedAttachmentId
            })
        else { return nil }
        
        let pageViewController: MediaPageViewController = MediaPageViewController(
            viewModel: viewModel,
            initialItem: initialItem,
            options: options
        )
        let navController: MediaGalleryNavigationController = MediaGalleryNavigationController()
        navController.viewControllers = [pageViewController]
        navController.modalPresentationStyle = .fullScreen
        navController.transitioningDelegate = pageViewController
        
        return navController
    }
    
    public static func createTileViewController(
        threadId: String,
        threadVariant: SessionThread.Variant,
        focusedAttachmentId: String?
    ) -> MediaTileViewController {
        let viewModel: MediaGalleryViewModel = MediaGalleryViewModel(
            threadId: threadId,
            threadVariant: threadVariant,
            pageSize: MediaTileViewController.itemPageSize,
            focusedAttachmentId: focusedAttachmentId
        )
        
        // Load the data for the album immediately (needed before pushing to the screen so
        // transitions work nicely)
        let pageTarget: PageInfo.Target = {
            // If we don't have a `focusedAttachmentId` then default to `.before` (it'll query
            // from a `0` offset
            guard let targetId: String = focusedAttachmentId else { return .before }
            
            return .around(id: targetId)
        }()
        let initialGalleryData: (sections: [SectionModel], pageInfo: PageInfo) = viewModel.updatedGalleryData(
            with: [],
            dataToUpsert: viewModel.loadGalleryPage(
                pageTarget,
                currentPageInfo: PageInfo(pageSize: MediaTileViewController.itemPageSize)
            )
        )
        
        viewModel.updateGalleryData(
            initialGalleryData.sections,
            pageInfo: initialGalleryData.pageInfo
        )
        
        return MediaTileViewController(
            viewModel: viewModel
        )
    }
}

// MARK: - Objective-C Support

// FIXME: Remove when we can

@objc(SNMediaGallery)
public class SNMediaGallery: NSObject {
    @objc(pushTileViewWithSliderEnabledForThreadId:isClosedGroup:isOpenGroup:fromNavController:)
    static func pushTileView(threadId: String, isClosedGroup: Bool, isOpenGroup: Bool, fromNavController: OWSNavigationController) {
        fromNavController.pushViewController(
            MediaGalleryViewModel.createTileViewController(
                threadId: threadId,
                threadVariant: {
                    if isClosedGroup { return .closedGroup }
                    if isOpenGroup { return .openGroup }

                    return .contact
                }(),
                focusedAttachmentId: nil
            ),
            animated: true
        )
    }
}
