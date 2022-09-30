// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalUtilitiesKit
import SessionUtilitiesKit

public class MediaGalleryViewModel {
    public typealias SectionModel = ArraySection<Section, Item>
    
    // MARK: - Section
    
    public enum Section: Differentiable, Equatable, Comparable, Hashable {
        case emptyGallery
        case loadOlder
        case galleryMonth(date: GalleryDate)
        case loadNewer
    }
    
    // MARK: Media type
    public enum MediaType {
        case media
        case document
    }
    
    // MARK: - Variables
    
    public let threadId: String
    public let threadVariant: SessionThread.Variant
    private var focusedAttachmentId: String?
    public private(set) var focusedIndexPath: IndexPath?
    public var mediaType: MediaType
    
    /// This value is the current state of an album view
    private var cachedInteractionIdBefore: Atomic<[Int64: Int64]> = Atomic([:])
    private var cachedInteractionIdAfter: Atomic<[Int64: Int64]> = Atomic([:])
    
    public var interactionIdBefore: [Int64: Int64] { cachedInteractionIdBefore.wrappedValue }
    public var interactionIdAfter: [Int64: Int64] { cachedInteractionIdAfter.wrappedValue }
    public private(set) var albumData: [Int64: [Item]] = [:]
    public private(set) var pagedDataObserver: PagedDatabaseObserver<Attachment, Item>?
    
    /// This value is the current state of a gallery view
    private var unobservedGalleryDataChanges: [SectionModel]?
    public private(set) var galleryData: [SectionModel] = []
    public var onGalleryChange: (([SectionModel]) -> ())? {
        didSet {
            // When starting to observe interaction changes we want to trigger a UI update just in case the
            // data was changed while we weren't observing
            if let unobservedGalleryDataChanges: [SectionModel] = self.unobservedGalleryDataChanges {
                onGalleryChange?(unobservedGalleryDataChanges)
                self.unobservedGalleryDataChanges = nil
            }
        }
    }
    
    // MARK: - Initialization
    
    init(
        threadId: String,
        threadVariant: SessionThread.Variant,
        isPagedData: Bool,
        mediaType: MediaType,
        pageSize: Int = 1,
        focusedAttachmentId: String? = nil,
        performInitialQuerySync: Bool = false
    ) {
        self.threadId = threadId
        self.threadVariant = threadVariant
        self.focusedAttachmentId = focusedAttachmentId
        self.pagedDataObserver = nil
        self.mediaType = mediaType
        
        guard isPagedData else { return }
     
        // Note: Since this references self we need to finish initializing before setting it, we
        // also want to skip the initial query and trigger it async so that the push animation
        // doesn't stutter (it should load basically immediately but without this there is a
        // distinct stutter)
        self.pagedDataObserver = PagedDatabaseObserver(
            pagedTable: Attachment.self,
            pageSize: pageSize,
            idColumn: .id,
            observedChanges: [
                PagedData.ObservedChanges(
                    table: Attachment.self,
                    columns: [.isValid]
                )
            ],
            joinSQL: Item.joinSQL,
            filterSQL: Item.filterSQL(threadId: threadId, mediaType: self.mediaType),
            orderSQL: Item.galleryOrderSQL,
            dataQuery: Item.baseQuery(orderSQL: Item.galleryOrderSQL),
            onChangeUnsorted: { [weak self] updatedData, updatedPageInfo in
                guard let updatedGalleryData: [SectionModel] = self?.process(data: updatedData, for: updatedPageInfo) else {
                    return
                }
                
                // If we have the 'onGalleryChange' callback then trigger it, otherwise just store the changes
                // to be sent to the callback if we ever start observing again (when we have the callback it needs
                // to do the data updating as it's tied to UI updates and can cause crashes if not updated in the
                // correct order)
                guard let onGalleryChange: (([SectionModel]) -> ()) = self?.onGalleryChange else {
                    self?.unobservedGalleryDataChanges = updatedGalleryData
                    return
                }

                onGalleryChange(updatedGalleryData)
            }
        )
        
        // Run the initial query on a backgorund thread so we don't block the push transition
        let loadInitialData: () -> () = { [weak self] in
            // If we don't have a `initialFocusedId` then default to `.pageBefore` (it'll query
            // from a `0` offset)
            guard let initialFocusedId: String = focusedAttachmentId else {
                self?.pagedDataObserver?.load(.pageBefore)
                return
            }
            
            self?.pagedDataObserver?.load(.initialPageAround(id: initialFocusedId))
        }
        
        // We have a custom transition when going from an attachment detail screen to the tile gallery
        // so in that case we want to perform the initial query synchronously so that we have the content
        // to do the transition (we don't clear the 'unobservedGalleryDataChanges' after setting it as
        // we don't want to mess with the initial view controller behaviour)
        guard !performInitialQuerySync else {
            loadInitialData()
            updateGalleryData(self.unobservedGalleryDataChanges ?? [])
            return
        }
        
        DispatchQueue.global(qos: .default).async {
            loadInitialData()
        }
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
    
    public struct Item: FetchableRecordWithRowId, Decodable, Identifiable, Differentiable, Equatable, Hashable {
        fileprivate static let interactionIdKey: SQL = SQL(stringLiteral: CodingKeys.interactionId.stringValue)
        fileprivate static let interactionVariantKey: SQL = SQL(stringLiteral: CodingKeys.interactionVariant.stringValue)
        fileprivate static let interactionAuthorIdKey: SQL = SQL(stringLiteral: CodingKeys.interactionAuthorId.stringValue)
        fileprivate static let interactionTimestampMsKey: SQL = SQL(stringLiteral: CodingKeys.interactionTimestampMs.stringValue)
        fileprivate static let rowIdKey: SQL = SQL(stringLiteral: CodingKeys.rowId.stringValue)
        fileprivate static let attachmentKey: SQL = SQL(stringLiteral: CodingKeys.attachment.stringValue)
        fileprivate static let attachmentAlbumIndexKey: SQL = SQL(stringLiteral: CodingKeys.attachmentAlbumIndex.stringValue)
        
        fileprivate static let attachmentString: String = CodingKeys.attachment.stringValue
        
        public var id: String { attachment.id }
        public var differenceIdentifier: String { attachment.id }
        
        let interactionId: Int64
        let interactionVariant: Interaction.Variant
        let interactionAuthorId: String
        let interactionTimestampMs: Int64
        
        public var rowId: Int64
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
        
        // MARK: - Query
        
        fileprivate static let joinSQL: SQL = {
            let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            return """
                JOIN \(InteractionAttachment.self) ON \(interactionAttachment[.attachmentId]) = \(attachment[.id])
                JOIN \(Interaction.self) ON \(interaction[.id]) = \(interactionAttachment[.interactionId])
            """
        }()
        
        fileprivate static func filterSQL(threadId: String, mediaType: MediaType) -> SQL {
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
            
            switch (mediaType) {
                case .media:
                    return SQL("""
                        \(attachment[.isVisualMedia]) = true AND
                        \(attachment[.isValid]) = true AND
                        \(interaction[.threadId]) = \(threadId)
                    """)
                case .document:
                    // FIXME: Remove "\(attachment[.sourceFilename]) <> 'session-audio-message'" when all platforms send the voice message properly
                    return SQL("""
                        \(attachment[.isVisualMedia]) = false AND
                        \(attachment[.isValid]) = true AND
                        \(interaction[.threadId]) = \(threadId) AND
                        \(attachment[.variant]) = \(Attachment.Variant.standard) AND
                        \(attachment[.sourceFilename]) <> 'session-audio-message'
                    """)
            }
        }
        
        fileprivate static let galleryOrderSQL: SQL = {
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            /// **Note:** This **MUST** match the desired sort behaviour for the screen otherwise paging will be
            /// very broken
            return SQL("\(interaction[.timestampMs].desc), \(interactionAttachment[.albumIndex])")
        }()
        
        fileprivate static let galleryReverseOrderSQL: SQL = {
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            /// **Note:** This **MUST** match the desired sort behaviour for the screen otherwise paging will be
            /// very broken
            return SQL("\(interaction[.timestampMs]), \(interactionAttachment[.albumIndex].desc)")
        }()
        
        fileprivate static func baseQuery(orderSQL: SQL, customFilters: SQL? = nil) -> (([Int64]) -> AdaptedFetchRequest<SQLRequest<Item>>) {
            return { rowIds -> AdaptedFetchRequest<SQLRequest<Item>> in
                let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
                let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
                
                let numColumnsBeforeLinkedRecords: Int = 6
                let finalFilterSQL: SQL = {
                    guard let customFilters: SQL = customFilters else {
                        return """
                            WHERE \(attachment.alias[Column.rowID]) IN \(rowIds)
                        """
                    }

                    return """
                        WHERE (
                            \(customFilters)
                        )
                    """
                }()
                let request: SQLRequest<Item> = """
                    SELECT
                        \(interaction[.id]) AS \(Item.interactionIdKey),
                        \(interaction[.variant]) AS \(Item.interactionVariantKey),
                        \(interaction[.authorId]) AS \(Item.interactionAuthorIdKey),
                        \(interaction[.timestampMs]) AS \(Item.interactionTimestampMsKey),

                        \(attachment.alias[Column.rowID]) AS \(Item.rowIdKey),
                        \(interactionAttachment[.albumIndex]) AS \(Item.attachmentAlbumIndexKey),
                        \(Item.attachmentKey).*
                    FROM \(Attachment.self)
                    \(joinSQL)
                    \(finalFilterSQL)
                    ORDER BY \(orderSQL)
                """
                
                return request.adapted { db in
                    let adapters = try splittingRowAdapters(columnCounts: [
                        numColumnsBeforeLinkedRecords,
                        Attachment.numberOfSelectedColumns(db)
                    ])

                    return ScopeAdapter([
                        Item.attachmentString: adapters[1]
                    ])
                }
            }
        }
        
        fileprivate static func baseQuery(orderSQL: SQL, customFilters: SQL) -> AdaptedFetchRequest<SQLRequest<Item>> {
            return Item.baseQuery(orderSQL: orderSQL, customFilters: customFilters)([])
        }

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
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    public typealias AlbumObservation = ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<[Item]>>>
    public lazy var observableAlbumData: AlbumObservation = buildAlbumObservation(for: nil)
    
    private func buildAlbumObservation(for interactionId: Int64?) -> AlbumObservation {
        return ValueObservation
            .trackingConstantRegion { db -> [Item] in
                guard let interactionId: Int64 = interactionId else { return [] }
                
                let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
                let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
                
                return try Item
                    .baseQuery(
                        orderSQL: SQL(interactionAttachment[.albumIndex]),
                        customFilters: SQL("""
                            \(attachment[.isValid]) = true AND
                            \(interaction[.id]) = \(interactionId)
                        """)
                    )
                    .fetchAll(db)
            }
            .removeDuplicates()
    }
    
    @discardableResult public func loadAndCacheAlbumData(for interactionId: Int64, in threadId: String) -> [Item] {
        typealias AlbumInfo = (albumData: [Item], interactionIdBefore: Int64?, interactionIdAfter: Int64?)
        
        // Note: It's possible we already have cached album data for this interaction
        // but to avoid displaying stale data we re-fetch from the database anyway
        let maybeAlbumInfo: AlbumInfo? = Storage.shared.read { db -> AlbumInfo in
            let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
            let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
            let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
            
            let newAlbumData: [Item] = try Item
                .baseQuery(
                    orderSQL: SQL(interactionAttachment[.albumIndex]),
                    customFilters: SQL("""
                        \(attachment[.isVisualMedia]) = true AND
                        \(attachment[.isValid]) = true AND
                        \(interaction[.id]) = \(interactionId)
                    """)
                )
                .fetchAll(db)
            
            guard let albumTimestampMs: Int64 = newAlbumData.first?.interactionTimestampMs else {
                return (newAlbumData, nil, nil)
            }
            
            let itemBefore: Item? = try Item
                .baseQuery(
                    orderSQL: Item.galleryReverseOrderSQL,
                    customFilters: SQL("""
                        \(attachment[.isVisualMedia]) = true AND
                        \(attachment[.isValid]) = true AND
                        \(interaction[.timestampMs]) > \(albumTimestampMs) AND
                        \(interaction[.threadId]) = \(threadId)
                    """)
                )
                .fetchOne(db)
            let itemAfter: Item? = try Item
                .baseQuery(
                    orderSQL: Item.galleryOrderSQL,
                    customFilters: SQL("""
                        \(attachment[.isVisualMedia]) = true AND
                        \(attachment[.isValid]) = true AND
                        \(interaction[.timestampMs]) < \(albumTimestampMs) AND
                        \(interaction[.threadId]) = \(threadId)
                    """)
                )
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
    
    // MARK: - Gallery
    
    private func process(data: [Item], for pageInfo: PagedData.PageInfo) -> [SectionModel] {
        let galleryData: [SectionModel] = data
            .grouped(by: \.galleryDate)
            .mapValues { sectionItems -> [Item] in
                sectionItems
                    .sorted { lhs, rhs -> Bool in
                        if lhs.interactionTimestampMs == rhs.interactionTimestampMs {
                            // Start of album first
                            return (lhs.attachmentAlbumIndex < rhs.attachmentAlbumIndex)
                        }
                        
                        // Newer interactions first
                        return (lhs.interactionTimestampMs > rhs.interactionTimestampMs)
                    }
            }
            .map { galleryDate, items in
                SectionModel(model: .galleryMonth(date: galleryDate), elements: items)
            }
        
        // Remove and re-add the custom sections as needed
        return [
            (data.isEmpty ? [SectionModel(section: .emptyGallery)] : []),
            (!data.isEmpty && pageInfo.pageOffset > 0 ? [SectionModel(section: .loadNewer)] : []),
            galleryData,
            (!data.isEmpty && (pageInfo.pageOffset + pageInfo.currentCount) < pageInfo.totalCount ?
                [SectionModel(section: .loadOlder)] :
                []
            )
        ]
        .flatMap { $0 }
        .sorted { lhs, rhs -> Bool in (lhs.model > rhs.model) }
    }
    
    public func updateGalleryData(_ updatedData: [SectionModel]) {
        self.galleryData = updatedData
        
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
            threadVariant: threadVariant,
            isPagedData: false,
            mediaType: .media
        )
        viewModel.loadAndCacheAlbumData(for: interactionId, in: threadId)
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
    
    public static func createMediaTileViewController(
        threadId: String,
        threadVariant: SessionThread.Variant,
        focusedAttachmentId: String?,
        performInitialQuerySync: Bool = false
    ) -> MediaTileViewController {
        let viewModel: MediaGalleryViewModel = MediaGalleryViewModel(
            threadId: threadId,
            threadVariant: threadVariant,
            isPagedData: true,
            mediaType: .media,
            pageSize: MediaTileViewController.itemPageSize,
            focusedAttachmentId: focusedAttachmentId,
            performInitialQuerySync: performInitialQuerySync
        )
        
        return MediaTileViewController(
            viewModel: viewModel
        )
    }
    
    public static func createDocumentTitleViewController(
        threadId: String,
        threadVariant: SessionThread.Variant,
        focusedAttachmentId: String?,
        performInitialQuerySync: Bool = false
    ) -> DocumentTileViewController {
        let viewModel: MediaGalleryViewModel = MediaGalleryViewModel(
            threadId: threadId,
            threadVariant: threadVariant,
            isPagedData: true,
            mediaType: .document,
            pageSize: MediaTileViewController.itemPageSize,
            focusedAttachmentId: focusedAttachmentId,
            performInitialQuerySync: performInitialQuerySync
        )
        
        return DocumentTileViewController(
            viewModel: viewModel
        )
    }
    
    public static func createAllMediaViewController(
        threadId: String,
        threadVariant: SessionThread.Variant,
        focusedAttachmentId: String?,
        performInitialQuerySync: Bool = false
    ) -> AllMediaViewController {
        let mediaTitleViewController = createMediaTileViewController(
            threadId: threadId,
            threadVariant: threadVariant,
            focusedAttachmentId: focusedAttachmentId,
            performInitialQuerySync: performInitialQuerySync
        )
        
        let documentTitleViewController = createDocumentTitleViewController(
            threadId: threadId,
            threadVariant: threadVariant,
            focusedAttachmentId: focusedAttachmentId,
            performInitialQuerySync: performInitialQuerySync
        )
        
        return AllMediaViewController(
            mediaTitleViewController: mediaTitleViewController,
            documentTitleViewController: documentTitleViewController
        )
    }
}

// MARK: - Objective-C Support

// FIXME: Remove when we can

@objc(SNMediaGallery)
public class SNMediaGallery: NSObject {
    @objc(pushTileViewWithSliderEnabledForThreadId:isClosedGroup:isOpenGroup:fromNavController:)
    static func pushTileView(threadId: String, isClosedGroup: Bool, isOpenGroup: Bool, fromNavController: UINavigationController) {
        fromNavController.pushViewController(
            MediaGalleryViewModel.createAllMediaViewController(
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
