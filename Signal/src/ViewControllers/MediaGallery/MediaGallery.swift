//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum GalleryDirection {
    case before, after, around
}

class MediaGalleryAlbum {

    private var originalItems: [MediaGalleryItem]
    var items: [MediaGalleryItem] {
        get {
            guard let mediaGallery = self.mediaGallery else {
                owsFailDebug("mediaGallery was unexpectedly nil")
                return originalItems
            }

            return originalItems.filter { !mediaGallery.deletedGalleryItems.contains($0) }
        }
    }

    weak var mediaGallery: MediaGallery?

    init(items: [MediaGalleryItem]) {
        self.originalItems = items
    }

    func add(item: MediaGalleryItem) {
        guard !originalItems.contains(item) else {
            return
        }

        originalItems.append(item)
        originalItems.sort { (lhs, rhs) -> Bool in
            return lhs.albumIndex < rhs.albumIndex
        }
    }
}

public class MediaGalleryItem: Equatable, Hashable {
    let message: TSMessage
    let attachmentStream: TSAttachmentStream
    let galleryDate: GalleryDate
    let captionForDisplay: String?
    let albumIndex: Int
    var album: MediaGalleryAlbum?
    let orderingKey: MediaGalleryItemOrderingKey

    init(message: TSMessage, attachmentStream: TSAttachmentStream) {
        self.message = message
        self.attachmentStream = attachmentStream
        self.captionForDisplay = attachmentStream.caption?.filterForDisplay
        self.galleryDate = GalleryDate(message: message)
        self.albumIndex = message.attachmentIds.firstIndex(of: attachmentStream.uniqueId) ?? 0
        self.orderingKey = MediaGalleryItemOrderingKey(messageSortKey: message.sortId, attachmentSortKey: albumIndex)
    }

    var isVideo: Bool {
        return attachmentStream.isVideo
    }

    var isAnimated: Bool {
        return attachmentStream.isAnimated
    }

    var isImage: Bool {
        return attachmentStream.isImage
    }

    var imageSize: CGSize {
        return attachmentStream.imageSize()
    }

    public typealias AsyncThumbnailBlock = (UIImage) -> Void
    func thumbnailImage(async:@escaping AsyncThumbnailBlock) -> UIImage? {
        return attachmentStream.thumbnailImageSmall(success: async, failure: {})
    }

    func thumbnailImageSync() -> UIImage? {
        return attachmentStream.thumbnailImageSmallSync()
    }

    // MARK: Equatable

    public static func == (lhs: MediaGalleryItem, rhs: MediaGalleryItem) -> Bool {
        return lhs.attachmentStream.uniqueId == rhs.attachmentStream.uniqueId
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(attachmentStream.uniqueId)
    }

    // MARK: Sorting

    struct MediaGalleryItemOrderingKey: Comparable {
        let messageSortKey: UInt64
        let attachmentSortKey: Int

        // MARK: Comparable

        static func < (lhs: MediaGalleryItem.MediaGalleryItemOrderingKey, rhs: MediaGalleryItem.MediaGalleryItemOrderingKey) -> Bool {
            if lhs.messageSortKey < rhs.messageSortKey {
                return true
            }

            if lhs.messageSortKey == rhs.messageSortKey {
                if lhs.attachmentSortKey < rhs.attachmentSortKey {
                    return true
                }
            }

            return false
        }
    }
}

public struct GalleryDate: Hashable, Comparable, Equatable {
    let year: Int
    let month: Int

    init(message: TSMessage) {
        let date = message.receivedAtDate()

        self.year = Calendar.current.component(.year, from: date)
        self.month = Calendar.current.component(.month, from: date)
    }

    init(year: Int, month: Int) {
        assert(month >= 1 && month <= 12)

        self.year = year
        self.month = month
    }

    private var isThisMonth: Bool {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let month = Calendar.current.component(.month, from: now)
        let thisMonth = GalleryDate(year: year, month: month)

        return self == thisMonth
    }

    public var date: Date {
        var components = DateComponents()
        components.month = self.month
        components.year = self.year

        return Calendar.current.date(from: components)!
    }

    private var isThisYear: Bool {
        let now = Date()
        let thisYear = Calendar.current.component(.year, from: now)

        return self.year == thisYear
    }

    static let thisYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"

        return formatter
    }()

    static let olderFormatter: DateFormatter = {
        let formatter = DateFormatter()

        // FIXME localize for RTL, or is there a built in way to do this?
        formatter.dateFormat = "MMMM yyyy"

        return formatter
    }()

    var localizedString: String {
        if isThisMonth {
            return NSLocalizedString("MEDIA_GALLERY_THIS_MONTH_HEADER", comment: "Section header in media gallery collection view")
        } else if isThisYear {
            return type(of: self).thisYearFormatter.string(from: self.date)
        } else {
            return type(of: self).olderFormatter.string(from: self.date)
        }
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(month)
        hasher.combine(year)
    }

    // MARK: Comparable

    public static func < (lhs: GalleryDate, rhs: GalleryDate) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        } else if lhs.month != rhs.month {
            return lhs.month < rhs.month
        } else {
            return false
        }
    }

    // MARK: Equatable

    public static func == (lhs: GalleryDate, rhs: GalleryDate) -> Bool {
        return lhs.month == rhs.month && lhs.year == rhs.year
    }
}

protocol MediaGalleryDelegate: class {
    func mediaGallery(_ mediaGallery: MediaGallery, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject)
    func mediaGallery(_ mediaGallery: MediaGallery, deletedSections: IndexSet, deletedItems: [IndexPath])
}

class MediaGallery {

    // MARK: - Dependencies

    private var audioPlayer: CVAudioPlayer {
        return AppEnvironment.shared.audioPlayer
    }

    // MARK: -

    var deletedAttachments: Set<TSAttachment> = Set()
    var deletedGalleryItems: Set<MediaGalleryItem> = Set()

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private let mediaGalleryFinder: AnyMediaGalleryFinder

    // we start with a small range size for quick loading.
    private let fetchRangeSize: UInt = 10

    deinit {
        Logger.debug("")
    }

    @objc
    init(thread: TSThread) {
        self.mediaGalleryFinder = AnyMediaGalleryFinder(thread: thread)

        setupDatabaseObservation()
    }

    func setupDatabaseObservation() {
        guard StorageCoordinator.dataStoreForUI == .grdb else {
            owsFailDebug("Invalid data store.")
            return
        }
        databaseStorage.appendUIDatabaseSnapshotDelegate(self)
    }

    // MARK: - 

    func process(deletedAttachmentIds: [String]) {
        let deletedItems: [MediaGalleryItem] = deletedAttachmentIds.compactMap { attachmentId in
            guard let deletedItem = self.galleryItems.first(where: { galleryItem in
                galleryItem.attachmentStream.uniqueId == attachmentId
            }) else {
                Logger.debug("deletedItem was never loaded - no need to remove.")
                return nil
            }

            return deletedItem
        }

        delete(items: deletedItems, initiatedBy: self, deleteFromDB: false)
    }

    // MARK: -

    var galleryItems: [MediaGalleryItem] = []
    var sections: [GalleryDate: [MediaGalleryItem]] = [:]
    var sectionDates: [GalleryDate] = []
    var hasFetchedOldest = false
    var hasFetchedMostRecent = false

    func buildGalleryItem(attachment: TSAttachment, transaction: SDSAnyReadTransaction) -> MediaGalleryItem? {
        guard let attachmentStream = attachment as? TSAttachmentStream else {
            owsFailDebug("gallery doesn't yet support showing undownloaded attachments")
            return nil
        }

        guard let message = attachmentStream.fetchAlbumMessage(transaction: transaction) else {
            owsFailDebug("message was unexpectedly nil")
            return nil
        }

        let galleryItem = MediaGalleryItem(message: message, attachmentStream: attachmentStream)
        galleryItem.album = getAlbum(item: galleryItem)

        return galleryItem
    }

    var galleryAlbums: [String: MediaGalleryAlbum] = [:]
    func getAlbum(item: MediaGalleryItem) -> MediaGalleryAlbum? {
        guard let albumMessageId = item.attachmentStream.albumMessageId else {
            return nil
        }

        guard let existingAlbum = galleryAlbums[albumMessageId] else {
            let newAlbum = MediaGalleryAlbum(items: [item])
            galleryAlbums[albumMessageId] = newAlbum
            newAlbum.mediaGallery = self
            return newAlbum
        }

        existingAlbum.add(item: item)
        return existingAlbum
    }

    // Range instead of indexSet since it's contiguous?
    var fetchedIndexSet = IndexSet() {
        didSet {
            Logger.debug("\(oldValue) -> \(fetchedIndexSet)")
        }
    }

    enum MediaGalleryError: Error {
        case itemNoLongerExists
    }

    // MARK: - Loading

    func ensureGalleryItemsLoaded(_ direction: GalleryDirection, item: MediaGalleryItem, amount: UInt, shouldLoadAlbumRemainder: Bool, completion: ((IndexSet, [IndexPath]) -> Void)? = nil ) {

        var galleryItems: [MediaGalleryItem] = self.galleryItems
        var sections: [GalleryDate: [MediaGalleryItem]] = self.sections
        var sectionDates: [GalleryDate] = self.sectionDates

        var newGalleryItems: [MediaGalleryItem] = []
        var newDates: [GalleryDate] = []

        do {
            try Bench(title: "fetching gallery items") {
                try self.databaseStorage.uiReadThrows { transaction in
                    guard let initialIndex = self.mediaGalleryFinder.mediaIndex(attachment: item.attachmentStream, transaction: transaction) else {
                        throw MediaGalleryError.itemNoLongerExists
                    }
                    let mediaCount: Int = Int(self.mediaGalleryFinder.mediaCount(transaction: transaction))

                    var albumRange: Range<Int>?
                    let requestRange: Range<Int> = { () -> Range<Int> in
                        var range: Range<Int> = { () -> Range<Int> in
                            switch direction {
                            case .around:
                                // To keep it simple, this isn't exactly *amount* sized if `message` window overlaps the end or
                                // beginning of the view. Still, we have sufficient buffer to fetch more as the user swipes.
                                let start: Int = initialIndex - Int(amount) / 2
                                let end: Int = initialIndex + Int(amount) / 2

                                return start..<end
                            case .before:
                                let start: Int = initialIndex + 1 - Int(amount)
                                let end: Int = initialIndex + 1

                                return start..<end
                            case  .after:
                                let start: Int = initialIndex
                                let end: Int = initialIndex  + Int(amount)

                                return start..<end
                            }
                        }()

                        if shouldLoadAlbumRemainder {
                            let albumStart = (initialIndex - item.albumIndex)
                            let albumEnd = albumStart + item.message.attachmentIds.count
                            albumRange = (albumStart..<albumEnd)
                            range = (min(range.lowerBound, albumStart)..<max(range.upperBound, albumEnd))
                        }

                        return range.clamped(to: 0..<mediaCount)
                    }()

                    let requestSet = IndexSet(integersIn: requestRange)
                    guard !self.fetchedIndexSet.contains(integersIn: requestSet) else {
                        Logger.debug("all requested messages have already been loaded.")
                        return
                    }

                    let unfetchedSet = requestSet.subtracting(self.fetchedIndexSet)

                    // For perf we only want to fetch a substantially full batch...
                    let isSubstantialRequest = unfetchedSet.count > (requestSet.count / 2)
                    // ...but we always fulfill even small requests if we're getting just the tail end of a gallery.
                    let isFetchingEdge = unfetchedSet.contains(0) || unfetchedSet.contains(Int(mediaCount - 1))

                    // If we're trying to load a complete album, and some of that album is unfetched...
                    let isLoadingAlbumRemainder: Bool
                    if let albumRange = albumRange {
                        isLoadingAlbumRemainder = unfetchedSet.intersects(integersIn: albumRange)
                    } else {
                        isLoadingAlbumRemainder = false
                    }

                    guard isSubstantialRequest || isFetchingEdge || isLoadingAlbumRemainder else {
                        Logger.debug("ignoring small fetch request: \(unfetchedSet.count)")
                        return
                    }

                    let firstUnfetchedIndex = unfetchedSet.min()!
                    let highestUnfetchedIndex = unfetchedSet.max()!
                    let nsRange: NSRange = NSRange(location: firstUnfetchedIndex, length: highestUnfetchedIndex - firstUnfetchedIndex + 1)
                    Logger.debug("fetching set: \(unfetchedSet), range: \(nsRange)")
                    self.mediaGalleryFinder.enumerateMediaAttachments(range: nsRange, transaction: transaction) { (attachment: TSAttachment) in

                        guard !self.deletedAttachments.contains(attachment) else {
                            Logger.debug("skipping \(attachment) which has been deleted.")
                            return
                        }

                        guard let item: MediaGalleryItem = self.buildGalleryItem(attachment: attachment, transaction: transaction) else {
                            owsFailDebug("unexpectedly failed to buildGalleryItem")
                            return
                        }

                        guard direction != .around || !galleryItems.contains(item) else {
                            // When loading "around" an item, we sometimes redunantly load some of
                            // the middle items. It's faster to skip them rather than doing two
                            // separate `before` and `after` queries.
                            Logger.debug("skipping redundant gallery item")
                            return
                        }

                        let date = item.galleryDate

                        galleryItems.append(item)
                        if sections[date] != nil {
                            sections[date]!.append(item)

                            // so we can update collectionView
                            newGalleryItems.append(item)
                        } else {
                            sectionDates.append(date)
                            sections[date] = [item]

                            // so we can update collectionView
                            newDates.append(date)
                            newGalleryItems.append(item)
                        }
                    }

                    self.fetchedIndexSet = self.fetchedIndexSet.union(unfetchedSet)
                    self.hasFetchedOldest = self.fetchedIndexSet.min() == 0
                    self.hasFetchedMostRecent = self.fetchedIndexSet.max() == mediaCount - 1
                }
            }
        } catch MediaGalleryError.itemNoLongerExists {
            Logger.debug("Ignoring reload, since item no longer exists.")
            return
        } catch {
            owsFailDebug("unexpected error: \(error)")
            return
        }

        // TODO only sort if changed
        var sortedSections: [GalleryDate: [MediaGalleryItem]] = [:]

        Bench(title: "sorting gallery items") {
            galleryItems.sort { lhs, rhs -> Bool in
                return lhs.orderingKey < rhs.orderingKey
            }
            sectionDates.sort()

            for (date, galleryItems) in sections {
                sortedSections[date] = galleryItems.sorted { lhs, rhs -> Bool in
                    return lhs.orderingKey < rhs.orderingKey
                }
            }
        }

        self.galleryItems = galleryItems
        self.sections = sortedSections
        self.sectionDates = sectionDates

        if let completionBlock = completion {
            Bench(title: "calculating changes for collectionView") {
                // FIXME can we avoid this index offset?
                let dateIndices = newDates.map { sectionDates.firstIndex(of: $0)! + 1 }
                let addedSections: IndexSet = IndexSet(dateIndices)

                let addedItems: [IndexPath] = newGalleryItems.map { galleryItem in
                    let sectionIdx = sectionDates.firstIndex(of: galleryItem.galleryDate)!
                    let section = sections[galleryItem.galleryDate]!
                    let itemIdx = section.firstIndex(of: galleryItem)!

                    // FIXME can we avoid this index offset?
                    return IndexPath(item: itemIdx, section: sectionIdx + 1)
                }

                completionBlock(addedSections, addedItems)
            }
        }
    }

    public func ensureLoadedForDetailView(focusedItem: MediaGalleryItem) {
        // For a speedy load, we only fetch a few items on either side of
        // the initial message
        ensureGalleryItemsLoaded(.around, item: focusedItem, amount: 10, shouldLoadAlbumRemainder: true)
    }

    func ensureLoadedForMostRecentTileView() -> MediaGalleryItem? {
        guard let mostRecentItem: MediaGalleryItem = (databaseStorage.uiRead { transaction in
            guard let attachment = self.mediaGalleryFinder.mostRecentMediaAttachment(transaction: transaction)  else {
                return nil
            }
            return self.buildGalleryItem(attachment: attachment, transaction: transaction)
        }) else {
            return nil
        }

        ensureGalleryItemsLoaded(.before, item: mostRecentItem, amount: 50, shouldLoadAlbumRemainder: false)
        return mostRecentItem
    }

    // MARK: -

    private var _delegates: [Weak<MediaGalleryDelegate>] = []

    var delegates: [MediaGalleryDelegate] {
        return _delegates.compactMap { $0.value }
    }

    func addDelegate(_ delegate: MediaGalleryDelegate) {
        _delegates = _delegates.filter({ $0.value != nil}) + [Weak(value: delegate)]
    }

    func delete(items: [MediaGalleryItem], initiatedBy: AnyObject, deleteFromDB: Bool) {
        AssertIsOnMainThread()

        guard items.count > 0 else {
            return
        }

        Logger.info("with items: \(items.map { ($0.attachmentStream, $0.message.timestamp) })")

        deletedGalleryItems.formUnion(items)
        delegates.forEach { $0.mediaGallery(self, willDelete: items, initiatedBy: initiatedBy) }

        for item in items {
            self.deletedAttachments.insert(item.attachmentStream)
        }

        if deleteFromDB {
            self.databaseStorage.asyncWrite { transaction in
                for item in items {
                    let message = item.message
                    let attachment = item.attachmentStream
                    message.removeAttachment(attachment, transaction: transaction)
                    if message.attachmentIds.count == 0 {
                        Logger.debug("removing message after removing last media attachment")
                        message.anyRemove(transaction: transaction)
                    }
                }
            }
        }

        var deletedSections: IndexSet = IndexSet()
        var deletedIndexPaths: [IndexPath] = []
        let originalSections = self.sections
        let originalSectionDates = self.sectionDates

        for item in items {
            guard let itemIndex = galleryItems.firstIndex(of: item) else {
                owsFailDebug("removing unknown item.")
                return
            }

            self.galleryItems.remove(at: itemIndex)

            guard let sectionIndex = sectionDates.firstIndex(where: { $0 == item.galleryDate }) else {
                owsFailDebug("item with unknown date.")
                return
            }

            guard var sectionItems = self.sections[item.galleryDate] else {
                owsFailDebug("item with unknown section")
                return
            }

            guard let sectionRowIndex = sectionItems.firstIndex(of: item) else {
                owsFailDebug("item with unknown sectionRowIndex")
                return
            }

            // We need to calculate the index of the deleted item with respect to it's original position.
            guard let originalSectionIndex = originalSectionDates.firstIndex(where: { $0 == item.galleryDate }) else {
                owsFailDebug("item with unknown date.")
                return
            }

            guard let originalSectionItems = originalSections[item.galleryDate] else {
                owsFailDebug("item with unknown section")
                return
            }

            guard let originalSectionRowIndex = originalSectionItems.firstIndex(of: item) else {
                owsFailDebug("item with unknown sectionRowIndex")
                return
            }

            if sectionItems == [item] {
                // Last item in section. Delete section.
                self.sections[item.galleryDate] = nil
                self.sectionDates.remove(at: sectionIndex)

                deletedSections.insert(originalSectionIndex + 1)
                deletedIndexPaths.append(IndexPath(row: originalSectionRowIndex, section: originalSectionIndex + 1))
            } else {
                sectionItems.remove(at: sectionRowIndex)
                self.sections[item.galleryDate] = sectionItems

                deletedIndexPaths.append(IndexPath(row: originalSectionRowIndex, section: originalSectionIndex + 1))
            }
        }

        delegates.forEach { $0.mediaGallery(self, deletedSections: deletedSections, deletedItems: deletedIndexPaths) }
    }

    let kGallerySwipeLoadBatchSize: UInt = 5

    internal func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("")

        self.ensureGalleryItemsLoaded(.after, item: currentItem, amount: kGallerySwipeLoadBatchSize, shouldLoadAlbumRemainder: true)

        guard let currentIndex = galleryItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let index: Int = galleryItems.index(after: currentIndex)
        guard let nextItem = galleryItems[safe: index] else {
            // already at last item
            return nil
        }

        guard !deletedGalleryItems.contains(nextItem) else {
            Logger.debug("nextItem was deleted - Recursing.")
            return galleryItem(after: nextItem)
        }

        return nextItem
    }

    internal func galleryItem(before currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("")

        self.ensureGalleryItemsLoaded(.before, item: currentItem, amount: kGallerySwipeLoadBatchSize, shouldLoadAlbumRemainder: true)

        guard let currentIndex = galleryItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let index: Int = galleryItems.index(before: currentIndex)
        guard let previousItem = galleryItems[safe: index] else {
            // already at first item
            return nil
        }

        guard !deletedGalleryItems.contains(previousItem) else {
            Logger.debug("previousItem was deleted - Recursing.")
            return galleryItem(before: previousItem)
        }

        return previousItem
    }

    var galleryItemCount: Int {
        let count: UInt = databaseStorage.uiRead { transaction in
            return self.mediaGalleryFinder.mediaCount(transaction: transaction)
        }
        return Int(count) - deletedAttachments.count
    }
}

extension MediaGallery: UIDatabaseSnapshotDelegate {

    func uiDatabaseSnapshotWillUpdate() {
        // no-op
    }

    func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        let deletedAttachmentIds = databaseChanges.attachmentDeletedUniqueIds
        guard deletedAttachmentIds.count > 0 else {
            return
        }
        process(deletedAttachmentIds: Array(deletedAttachmentIds))
    }

    func uiDatabaseSnapshotDidUpdateExternally() {
        // no-op
    }

    func uiDatabaseSnapshotDidReset() {
        // no-op
    }
}
