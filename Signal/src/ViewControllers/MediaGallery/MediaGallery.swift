//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

    fileprivate init(items: [MediaGalleryItem], mediaGallery: MediaGallery) {
        self.originalItems = items
        self.mediaGallery = mediaGallery
    }
}

public class MediaGalleryItem: Equatable, Hashable, MediaGallerySectionItem {
    let message: TSMessage
    let attachmentStream: TSAttachmentStream
    let galleryDate: GalleryDate
    let captionForDisplay: String?
    let albumIndex: Int
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
        return attachmentStream.isVideo && !attachmentStream.isLoopingVideo
    }

    var isAnimated: Bool {
        return attachmentStream.isAnimated || attachmentStream.isLoopingVideo
    }

    var isImage: Bool {
        return attachmentStream.isImage
    }

    // TODO: Add units to name.
    var imageSize: CGSize {
        attachmentStream.imageSizePoints
    }

    var uniqueId: String { attachmentStream.uniqueId }

    public typealias AsyncThumbnailBlock = (UIImage) -> Void
    func thumbnailImage(async: @escaping AsyncThumbnailBlock) -> UIImage? {
        attachmentStream.thumbnailImageSmall(success: async, failure: {})
        return nil
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

/// A "date" (actually an interval, such as a month) that represents a single section in a MediaGallery.
///
/// GalleryDates must be non-overlapping.
struct GalleryDate: Hashable, Comparable, Equatable {
    let interval: DateInterval

    init(message: TSMessage) {
        let date = message.receivedAtDate
        self.init(date: date)
    }

    init(date: Date) {
        self.interval = Calendar.current.dateInterval(of: .month, for: date)!
    }

    private var isThisMonth: Bool {
        return interval.contains(Date())
    }

    private var isThisYear: Bool {
        return Calendar.current.isDate(Date(), equalTo: interval.start, toGranularity: .year)
    }

    static let thisYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    static let olderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()

    var localizedString: String {
        if isThisMonth {
            return NSLocalizedString("MEDIA_GALLERY_THIS_MONTH_HEADER", comment: "Section header in media gallery collection view")
        } else if isThisYear {
            return type(of: self).thisYearFormatter.string(from: self.interval.start)
        } else {
            return type(of: self).olderFormatter.string(from: self.interval.start)
        }
    }

    // MARK: Comparable

    static func < (lhs: GalleryDate, rhs: GalleryDate) -> Bool {
        // Check for incorrectly-overlapping ranges.
        owsAssertDebug(lhs.interval == rhs.interval ||
                        !lhs.interval.intersects(rhs.interval) ||
                        lhs.interval.start == rhs.interval.end ||
                        lhs.interval.end == rhs.interval.start)
        return lhs.interval.start < rhs.interval.start
    }
}

protocol MediaGalleryDelegate: AnyObject {
    func mediaGallery(_ mediaGallery: MediaGallery, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject)
    func mediaGallery(_ mediaGallery: MediaGallery, deletedSections: IndexSet, deletedItems: [IndexPath])

    func mediaGallery(_ mediaGallery: MediaGallery, didReloadItemsInSections sections: IndexSet)
}

/// A backing store for media views (page-based or tile-based)
///
/// MediaGallery models a list of GalleryDate-based sections, each of which has a certain number of items.
/// Sections are loaded on demand (that is, there may be newer and older sections that are not in the model), and always
/// know their number of items. Items are also loaded on demand, potentially non-contiguously.
///
/// This model is designed around the needs of UICollectionView, but it also supports flat views of media.
class MediaGallery: Dependencies {

    private var deletedAttachmentIds: Set<String> = Set() {
        didSet {
            AssertIsOnMainThread()
        }
    }
    fileprivate var deletedGalleryItems: Set<MediaGalleryItem> = Set() {
        didSet {
            AssertIsOnMainThread()
        }
    }
    private var isCurrentlyProcessingExternalDeletion = false

    private let mediaGalleryFinder: MediaGalleryFinder
    private var sections: MediaGallerySections<Loader>!

    deinit {
        Logger.debug("")
    }

    @objc
    init(thread: TSThread) {
        self.mediaGalleryFinder = MediaGalleryFinder(thread: thread)
        self.sections = MediaGallerySections(loader: Loader(mediaGallery: self))
        setupDatabaseObservation()
    }

    func setupDatabaseObservation() {
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    // MARK: - 

    func process(deletedAttachmentIds incomingDeletedAttachmentIds: Set<String>) {
        AssertIsOnMainThread()

        let newlyDeletedAttachmentIds = incomingDeletedAttachmentIds.subtracting(deletedAttachmentIds)
        guard !newlyDeletedAttachmentIds.isEmpty else {
            return
        }

        guard !sections.isEmpty else {
            // Haven't loaded anything yet.
            return
        }

        var deletedItems: [MediaGalleryItem] = []
        var deletedIndexPaths: [IndexPath] = []

        let allPaths = sequence(first: IndexPath(item: 0, section: 0), next: { self.sections.indexPath(after: $0) })
        // This is not very efficient, but we have no index of attachment IDs -> loaded items.
        // An alternate approach would be to load the deleted attachments and check them by section.
        for path in allPaths {
            guard let loadedItem = galleryItem(at: path) else {
                continue
            }
            if newlyDeletedAttachmentIds.contains(loadedItem.attachmentStream.uniqueId) {
                deletedItems.append(loadedItem)
                deletedIndexPaths.append(path)
            }
        }

        delete(items: deletedItems, atIndexPaths: deletedIndexPaths, initiatedBy: self, deleteFromDB: false)
    }

    func process(newAttachmentIds: Set<String>) {
        AssertIsOnMainThread()

        guard !newAttachmentIds.isEmpty else {
            return
        }

        var sectionsNeedingUpdate = IndexSet()

        databaseStorage.read { transaction in
            for attachmentId in newAttachmentIds {
                let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction)
                guard let attachmentStream = attachment as? TSAttachmentStream else {
                    // not downloaded yet
                    return
                }
                guard let message = attachmentStream.fetchAlbumMessage(transaction: transaction) else {
                    Logger.warn("message was unexpectedly nil")
                    return
                }

                let sectionDate = GalleryDate(message: message)
                // Do a backwards search assuming new messages usually arrive at the end.
                // Still, this is kept sorted, so we ought to be able to do a binary search instead.
                if let sectionIndex = sections.sectionDates.lastIndex(of: sectionDate) {
                    sectionsNeedingUpdate.insert(sectionIndex)
                }
            }

            for sectionIndex in sectionsNeedingUpdate {
                // Throw out everything in that section.
                let sectionDate = sections.sectionDates[sectionIndex]
                sections.reloadSection(for: sectionDate, transaction: transaction)
            }
        }

        delegates.forEach { $0.mediaGallery(self, didReloadItemsInSections: sectionsNeedingUpdate) }
    }

    // MARK: -

    internal var hasFetchedOldest: Bool { sections.hasFetchedOldest }
    internal var hasFetchedMostRecent: Bool { sections.hasFetchedMostRecent }
    internal var galleryDates: [GalleryDate] { sections.sectionDates }

    private func buildGalleryItem(attachment: TSAttachment, transaction: SDSAnyReadTransaction) -> MediaGalleryItem? {
        guard let attachmentStream = attachment as? TSAttachmentStream else {
            owsFailDebug("gallery doesn't yet support showing undownloaded attachments")
            return nil
        }

        guard let message = attachmentStream.fetchAlbumMessage(transaction: transaction) else {
            owsFailDebug("message was unexpectedly nil")
            return nil
        }

        return MediaGalleryItem(message: message, attachmentStream: attachmentStream)
    }

    internal func album(for item: MediaGalleryItem) -> MediaGalleryAlbum {
        ensureGalleryItemsLoaded(.around,
                                 item: item,
                                 amount: kGallerySwipeLoadBatchSize,
                                 shouldLoadAlbumRemainder: true)

        // We get the path after loading items because loading can result in a shift of section indexes.
        guard let itemPath = indexPath(for: item) else {
            owsFailDebug("asking for album for an item that hasn't been loaded")
            return MediaGalleryAlbum(items: [item], mediaGallery: self)
        }

        let section = sections.itemsBySection[itemPath.section].value
        let startOfAlbum = section[..<itemPath.item].suffix { $0?.message.uniqueId == item.message.uniqueId }.startIndex
        let endOfAlbum = section[itemPath.item...].prefix { $0?.message.uniqueId == item.message.uniqueId }.endIndex
        let items = section[startOfAlbum..<endOfAlbum].map { $0! }

        return MediaGalleryAlbum(items: items, mediaGallery: self)
    }

    // MARK: - Loading

    /// Loads more items relative to the path `(sectionIndex, itemIndex)`.
    ///
    /// If `direction` is anything but `after`, section indexes may be invalidated.
    internal func ensureGalleryItemsLoaded(_ direction: GalleryDirection,
                                           sectionIndex: Int,
                                           itemIndex: Int,
                                           amount: Int,
                                           shouldLoadAlbumRemainder: Bool,
                                           completion: ((_ newSections: IndexSet) -> Void)? = nil) {
        guard !isCurrentlyProcessingExternalDeletion else {
            owsFailDebug("cannot access database while model is being updated")
            return
        }

        let anchorItem: MediaGalleryItem? = sections.loadedItem(at: IndexPath(item: itemIndex, section: sectionIndex))

        // May include a negative start location.
        let naiveRequestRange: Range<Int> = {
            let range: Range<Int> = {
                switch direction {
                case .around:
                    // To keep it simple, this isn't exactly *amount* sized if `message` window overlaps the end or
                    // beginning of the view. Still, we have sufficient buffer to fetch more as the user swipes.
                    let start: Int = itemIndex - Int(amount) / 2
                    let end: Int = itemIndex + Int(amount) / 2

                    return start..<end
                case .before:
                    let start: Int = itemIndex + 1 - Int(amount)
                    let end: Int = itemIndex + 1

                    return start..<end
                case .after:
                    let start: Int = itemIndex
                    let end: Int = itemIndex + Int(amount)

                    return start..<end
                }
            }()

            if shouldLoadAlbumRemainder, let item = anchorItem {
                let albumStart = (itemIndex - item.albumIndex)
                let albumEnd = albumStart + item.message.attachmentIds.count
                return (min(range.lowerBound, albumStart)..<max(range.upperBound, albumEnd))
            }

            return range
        }()

        func isSubstantialRequest() -> Bool {
            // If we have not loaded the item at the given path yet, it's substantial.
            guard let item = anchorItem else {
                return true
            }

            let sectionItems = sections.itemsBySection[sectionIndex].value

            // If we're loading the remainder of an album, check to see if any items in the album are not loaded yet.
            if shouldLoadAlbumRemainder {
                let albumStart = (itemIndex - item.albumIndex)
                    .clamp(sectionItems.startIndex, sectionItems.endIndex)
                let albumEnd = (albumStart + item.message.attachmentIds.count)
                    .clamp(sectionItems.startIndex, sectionItems.endIndex)
                if sectionItems[albumStart..<albumEnd].contains(nil) { return true }
            }

            // Count unfetched items forward and backward.
            func countUnfetched(in slice: ArraySlice<MediaGalleryItem?>) -> Int {
                return slice.lazy.filter { $0 == nil }.count
            }

            owsAssertDebug(naiveRequestRange.lowerBound < sectionItems.count)
            let sectionSliceStart = naiveRequestRange.lowerBound
                .clamp(sectionItems.startIndex, sectionItems.endIndex)
            let sectionSliceEnd = naiveRequestRange.upperBound
                .clamp(sectionItems.startIndex, sectionItems.endIndex)
            let sectionSlice = sectionItems[sectionSliceStart..<sectionSliceEnd]
            var unfetchedCount = countUnfetched(in: sectionSlice)

            if naiveRequestRange.upperBound > sectionItems.count {
                var currentSectionIndex = sectionIndex + 1
                var remainingForward = naiveRequestRange.upperBound - sectionItems.count
                repeat {
                    guard let currentSectionItems = sections.itemsBySection[safe: currentSectionIndex]?.value else {
                        // We've reached the end of the fetched sections. If there are more sections, or the last item
                        // isn't fetched yet, assume it's substantial.
                        if !hasFetchedMostRecent || (sections.itemsBySection.last?.value.last ?? nil) == nil {
                            return true
                        }
                        break
                    }
                    unfetchedCount += countUnfetched(in: currentSectionItems.prefix(remainingForward))
                    if remainingForward <= currentSectionItems.count {
                        break
                    }
                    remainingForward -= currentSectionItems.count
                    currentSectionIndex += 1
                } while true
            }

            if naiveRequestRange.lowerBound < 0 {
                var currentSectionIndex = sectionIndex - 1
                var remainingBackward = -naiveRequestRange.lowerBound
                repeat {
                    guard let currentSectionItems = sections.itemsBySection[safe: currentSectionIndex]?.value else {
                        // We've reached the start of the fetched sections. If there are more sections, or the first
                        // item isn't fetched yet, assume it's substantial.
                        if !hasFetchedOldest || (sections.itemsBySection.first?.value.first ?? nil) == nil {
                            return true
                        }
                        break
                    }
                    unfetchedCount += countUnfetched(in: currentSectionItems.suffix(remainingBackward))
                    if remainingBackward <= currentSectionItems.count {
                        break
                    }
                    remainingBackward -= currentSectionItems.count
                    currentSectionIndex -= 1
                } while true
            }

            // If we haven't hit the start or end, and more than half the items are unfetched, it's substantial.
            return unfetchedCount > (naiveRequestRange.count / 2)
        }

        guard isSubstantialRequest() else {
            return
        }

        let newlyLoadedSections = sections.ensureItemsLoaded(in: naiveRequestRange, relativeToSection: sectionIndex)
        completion?(newlyLoadedSections)
    }

    private func ensureGalleryItemsLoaded(_ direction: GalleryDirection,
                                          item: MediaGalleryItem,
                                          amount: Int,
                                          shouldLoadAlbumRemainder: Bool) {
        guard let path = indexPath(for: item) else {
            owsFailDebug("showing detail view for an item that hasn't been loaded: \(item.attachmentStream)")
            return
        }

        ensureGalleryItemsLoaded(direction,
                                 sectionIndex: path.section,
                                 itemIndex: path.item,
                                 amount: amount,
                                 shouldLoadAlbumRemainder: shouldLoadAlbumRemainder)
    }

    internal func ensureLoadedForDetailView(focusedAttachment: TSAttachment) -> MediaGalleryItem? {
        let newItem: MediaGalleryItem? = databaseStorage.read { transaction in
            guard let focusedItem = buildGalleryItem(attachment: focusedAttachment, transaction: transaction) else {
                return nil
            }

            guard let offsetInSection = mediaGalleryFinder.mediaIndex(of: focusedItem.attachmentStream,
                                                                      in: focusedItem.galleryDate.interval,
                                                                      excluding: deletedAttachmentIds,
                                                                      transaction: transaction.unwrapGrdbRead) else {
                owsFailDebug("showing detail for item not in the database")
                return nil
            }

            if sections.isEmpty {
                // Set up the current section only.
                sections.loadInitialSection(for: focusedItem.galleryDate, transaction: transaction)
            }

            return sections.getOrReplaceItem(focusedItem, offsetInSection: offsetInSection)
        }

        guard let focusedItem = newItem else {
            return nil
        }

        // For a speedy load, we only fetch a few items on either side of
        // the initial message
        ensureGalleryItemsLoaded(.around,
                                 item: focusedItem,
                                 amount: kGallerySwipeLoadBatchSize * 2,
                                 shouldLoadAlbumRemainder: true)

        return focusedItem
    }

    // MARK: - Section-based API

    internal func numberOfItemsInSection(_ sectionIndex: Int) -> Int {
        return sections.itemsBySection[sectionIndex].value.count
    }

    /// Loads at least one section before the oldest section, though not any of the items in it.
    ///
    /// Operates in bulk in an attempt to cut down on database traffic, meaning it may measure multiple sections at once.
    ///
    /// Returns the number of new sections loaded, which can be used to update section indexes.
    internal func loadEarlierSections(batchSize: Int, transaction: SDSAnyReadTransaction) -> Int {
        return sections.loadEarlierSections(batchSize: batchSize, transaction: transaction)
    }

    /// Loads at least one section after the latest section, though not any of the items in it.
    ///
    /// Operates in bulk in an attempt to cut down on database traffic, meaning it may measure multiple sections at once.
    ///
    /// Returns the number of new sections loaded.
    internal func loadLaterSections(batchSize: Int, transaction: SDSAnyReadTransaction) -> Int {
        return sections.loadLaterSections(batchSize: batchSize, transaction: transaction)
    }

    // MARK: -

    private var _delegates: [Weak<MediaGalleryDelegate>] = []

    private var delegates: [MediaGalleryDelegate] {
        return _delegates.compactMap { $0.value }
    }

    internal func addDelegate(_ delegate: MediaGalleryDelegate) {
        _delegates = _delegates.filter({ $0.value != nil}) + [Weak(value: delegate)]
    }

    internal func delete(items: [MediaGalleryItem],
                         atIndexPaths givenIndexPaths: [IndexPath]? = nil,
                         initiatedBy: AnyObject,
                         deleteFromDB: Bool) {
        AssertIsOnMainThread()

        guard items.count > 0 else {
            return
        }

        Logger.info("with items: \(items.map { ($0.attachmentStream, $0.message.timestamp) })")
        isCurrentlyProcessingExternalDeletion = !deleteFromDB
        defer { isCurrentlyProcessingExternalDeletion = false }

        deletedGalleryItems.formUnion(items)
        delegates.forEach { $0.mediaGallery(self, willDelete: items, initiatedBy: initiatedBy) }

        if deleteFromDB {
            deletedAttachmentIds.formUnion(items.lazy.map { $0.attachmentStream.uniqueId })

            self.databaseStorage.asyncWrite { transaction in
                do {
                    for item in items {
                        let message = item.message
                        let attachment = item.attachmentStream
                        message.removeAttachment(attachment, transaction: transaction)
                        // We always have to check the database in case we do more than one deletion (at a time or in a
                        // row) without reloading existing media items and their associated message models.
                        var shouldDeleteMessage = message.attachmentIds.isEmpty
                        if !shouldDeleteMessage {
                            let upToDateAttachmentCount = try self.mediaGalleryFinder.countAllAttachments(
                                of: message,
                                transaction: transaction.unwrapGrdbRead)
                            if upToDateAttachmentCount == 0 {
                                // Refresh attachment list on the model, so deletion doesn't try to remove them again.
                                message.anyReload(transaction: transaction)
                                shouldDeleteMessage = true
                            }
                        }
                        if shouldDeleteMessage {
                            Logger.debug("removing message after removing last media attachment")
                            message.anyRemove(transaction: transaction)
                        }
                    }

                    transaction.addAsyncCompletionOnMain {
                        self.deletedAttachmentIds.subtract(items.lazy.map { $0.attachmentStream.uniqueId })
                    }
                } catch {
                    owsFailDebug("database error: \(error)")
                }
            }
        }

        var deletedIndexPaths: [IndexPath]
        if let indexPaths = givenIndexPaths {
            if OWSIsDebugBuild() {
                for (item, path) in zip(items, indexPaths) {
                    owsAssertDebug(item == sections.loadedItem(at: path), "paths not in sync with items")
                }
            }
            deletedIndexPaths = indexPaths
        } else {
            deletedIndexPaths = items.compactMap { sections.indexPath(for: $0) }
            owsAssertDebug(deletedIndexPaths.count == items.count, "removing an item that wasn't loaded")
        }
        deletedIndexPaths.sort()

        let deletedSections = sections.removeLoadedItems(atIndexPaths: deletedIndexPaths)

        isCurrentlyProcessingExternalDeletion = false

        delegates.forEach { $0.mediaGallery(self, deletedSections: deletedSections, deletedItems: deletedIndexPaths) }
    }

    // MARK: -

    /// Searches the appropriate section for this item.
    ///
    /// Will return nil if the item was not loaded through the gallery.
    internal func indexPath(for item: MediaGalleryItem) -> IndexPath? {
        return sections.indexPath(for: item)
    }

    /// Returns the item at `path`, which will be `nil` if not yet loaded.
    ///
    /// `path` must be a valid path for the items currently loaded.
    internal func galleryItem(at path: IndexPath) -> MediaGalleryItem? {
        return sections.loadedItem(at: path)
    }

    private let kGallerySwipeLoadBatchSize: Int = 5

    internal func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("")
        return galleryItem(.after, item: currentItem)
    }

    internal func galleryItem(before currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("")
        return galleryItem(.before, item: currentItem)
    }

    private func galleryItem(_ direction: GalleryDirection, item currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        let advance: (IndexPath) -> IndexPath?
        switch direction {
        case .around:
            owsFailDebug("should not use this function with .around")
            return currentItem
        case .before:
            advance = { self.sections.indexPath(before: $0) }
        case .after:
            advance = { self.sections.indexPath(after: $0) }
        }

        if !isCurrentlyProcessingExternalDeletion {
            self.ensureGalleryItemsLoaded(direction,
                                          item: currentItem,
                                          amount: kGallerySwipeLoadBatchSize,
                                          shouldLoadAlbumRemainder: true)
        }

        guard let currentPath = indexPath(for: currentItem) else {
            owsFailDebug("current item not found")
            return nil
        }

        // Repeatedly calling indexPath(before:) or indexPath(after:) isn't super efficient,
        // but we don't expect it to be more than a few steps.
        let laterItemPaths = sequence(first: currentPath, next: advance).dropFirst()
        for nextPath in laterItemPaths {
            guard let loadedNextItem = galleryItem(at: nextPath) else {
                owsAssertDebug(isCurrentlyProcessingExternalDeletion,
                               "should have loaded the next item already")
                return nil
            }

            if !deletedGalleryItems.contains(loadedNextItem) {
                return loadedNextItem
            }
        }

        // already at last item
        return nil
    }

    internal var galleryItemCount: Int {
        return databaseStorage.read { transaction in
            return Int(mediaGalleryFinder.mediaCount(excluding: deletedAttachmentIds,
                                                     transaction: transaction.unwrapGrdbRead))
        }
    }
}

extension MediaGallery: DatabaseChangeDelegate {

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        // Process deletions before insertions,
        // because we can modify our existing model for deletions but have to reset with insertions.
        process(deletedAttachmentIds: databaseChanges.attachmentDeletedUniqueIds)
        process(newAttachmentIds: databaseChanges.attachmentUniqueIds)
    }

    func databaseChangesDidUpdateExternally() {
        // no-op
    }

    func databaseChangesDidReset() {
        // no-op
    }
}

extension MediaGallery {
    internal struct Loader: MediaGallerySectionLoader {
        typealias EnumerationCompletion = MediaGalleryFinder.EnumerationCompletion
        typealias Item = MediaGalleryItem

        fileprivate unowned var mediaGallery: MediaGallery

        func numberOfItemsInSection(for date: GalleryDate, transaction: SDSAnyReadTransaction) -> Int {
            Int(mediaGallery.mediaGalleryFinder.mediaCount(in: date.interval,
                                                            excluding: mediaGallery.deletedAttachmentIds,
                                                            transaction: transaction.unwrapGrdbRead))
        }

        func enumerateTimestamps(before date: Date,
                                 count: Int,
                                 transaction: SDSAnyReadTransaction,
                                 block: (Date) -> Void) -> EnumerationCompletion {
            mediaGallery.mediaGalleryFinder.enumerateTimestamps(before: date,
                                                                excluding: mediaGallery.deletedAttachmentIds,
                                                                count: count,
                                                                transaction: transaction.unwrapGrdbRead,
                                                                block: block)
        }

        func enumerateTimestamps(after date: Date,
                                 count: Int,
                                 transaction: SDSAnyReadTransaction,
                                 block: (Date) -> Void) -> EnumerationCompletion {
            mediaGallery.mediaGalleryFinder.enumerateTimestamps(after: date,
                                                                excluding: mediaGallery.deletedAttachmentIds,
                                                                count: count,
                                                                transaction: transaction.unwrapGrdbRead,
                                                                block: block)
        }

        func enumerateItems(in interval: DateInterval,
                            range: Range<Int>,
                            transaction: SDSAnyReadTransaction,
                            block: (_ offset: Int, _ uniqueId: String, _ buildItem: () -> MediaGalleryItem) -> Void) {
            mediaGallery.mediaGalleryFinder.enumerateMediaAttachments(in: interval,
                                                                      excluding: mediaGallery.deletedAttachmentIds,
                                                                      range: NSRange(range),
                                                                      transaction: transaction.unwrapGrdbRead) {
                offset, attachment in

                block(offset, attachment.uniqueId) {
                    guard let item: MediaGalleryItem = mediaGallery.buildGalleryItem(attachment: attachment,
                                                                                     transaction: transaction) else {
                        owsFail("unexpectedly failed to buildGalleryItem for attachment #\(offset) \(attachment)")
                    }
                    return item
                }
            }
        }
    }
}
