//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
        let date = message.receivedAtDate()
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
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    static let olderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
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

    deinit {
        Logger.debug("")
    }

    @objc
    init(thread: TSThread) {
        self.mediaGalleryFinder = MediaGalleryFinder(thread: thread)

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

        let allPaths = sequence(first: IndexPath(item: 0, section: 0), next: { self.indexPath(after: $0) })
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

        databaseStorage.uiRead { transaction in
            for attachmentId in newAttachmentIds {
                let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction)
                guard let attachmentStream = attachment as? TSAttachmentStream else {
                    // not downloaded yet
                    return
                }
                guard let message = attachmentStream.fetchAlbumMessage(transaction: transaction) else {
                    owsFailDebug("message was unexpectedly nil")
                    return
                }

                let sectionDate = GalleryDate(message: message)
                // Do a backwards search assuming new messages usually arrive at the end.
                // Still, this is kept sorted, so we ought to be able to do a binary search instead.
                if let sectionIndex = sections.orderedKeys.lastIndex(of: sectionDate) {
                    sectionsNeedingUpdate.insert(sectionIndex)
                }
            }

            for sectionIndex in sectionsNeedingUpdate {
                // Throw out everything in that section.
                let sectionDate = sections.orderedKeys[sectionIndex]
                let newCount = numberOfItemsInSection(for: sectionDate, transaction: transaction)
                sections.replace(key: sectionDate, value: Array(repeating: nil, count: newCount))
            }
        }

        delegates.forEach { $0.mediaGallery(self, didReloadItemsInSections: sectionsNeedingUpdate) }
    }

    // MARK: -

    /// All sections we know about.
    ///
    /// Each section contains an array of possibly-fetched items.
    /// The length of the array is always the correct number of items in the section.
    /// The keys are kept in sorted order.
    private(set) var sections: OrderedDictionary<GalleryDate, [MediaGalleryItem?]> = OrderedDictionary()
    private(set) var hasFetchedOldest = false
    private(set) var hasFetchedMostRecent = false

    private func buildGalleryItem(attachment: TSAttachment, transaction: SDSAnyReadTransaction) -> MediaGalleryItem? {
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

        let anchorItem: MediaGalleryItem? = sections[sectionIndex].value[safe: itemIndex] ?? nil

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

            let sectionItems = sections[sectionIndex].value

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
                    guard let currentSectionItems = sections[safe: currentSectionIndex]?.value else {
                        // We've reached the end of the fetched sections. If there are more sections, or the last item
                        // isn't fetched yet, assume it's substantial.
                        if !hasFetchedMostRecent || (sections.last?.value.last ?? nil) == nil {
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
                    guard let currentSectionItems = sections[safe: currentSectionIndex]?.value else {
                        // We've reached the start of the fetched sections. If there are more sections, or the first
                        // item isn't fetched yet, assume it's substantial.
                        if !hasFetchedOldest || (sections.first?.value.first ?? nil) == nil {
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

        var numNewlyLoadedEarlierSections: Int = 0
        var numNewlyLoadedLaterSections: Int = 0

        Bench(title: "fetching gallery items") {
            self.databaseStorage.uiRead { transaction in
                // Figure out the earliest section this request will cross.
                var currentSectionIndex = sectionIndex
                var requestRange = NSRange(naiveRequestRange)
                while requestRange.location < 0 {
                    if currentSectionIndex == 0 {
                        let newlyLoadedCount = loadEarlierSections(batchSize: amount, transaction: transaction)
                        currentSectionIndex = newlyLoadedCount
                        numNewlyLoadedEarlierSections += newlyLoadedCount

                        if currentSectionIndex == 0 {
                            owsAssertDebug(hasFetchedOldest)
                            requestRange.location = 0
                            break
                        }
                    }

                    currentSectionIndex -= 1
                    let items = sections[currentSectionIndex].value
                    requestRange.location += items.count
                }

                let interval = DateInterval(start: sections.orderedKeys[currentSectionIndex].interval.start,
                                            end: .distantFutureForMillisecondTimestamp)

                var offset = 0
                mediaGalleryFinder.enumerateMediaAttachments(in: interval,
                                                             excluding: deletedAttachmentIds,
                                                             range: requestRange,
                                                             transaction: transaction.unwrapGrdbRead) { i, attachment in
                    owsAssertDebug(i >= offset, "does not support reverse traversal")

                    func tryAddNewItem() {
                        if currentSectionIndex >= sections.count {
                            if hasFetchedMostRecent {
                                // Ignore later attachments.
                                owsAssertDebug(sections.count == 1, "should only be used in single-album page view")
                                return
                            }
                            numNewlyLoadedLaterSections += loadLaterSections(batchSize: amount,
                                                                             transaction: transaction)
                            if currentSectionIndex >= sections.count {
                                owsFailDebug("attachment \(attachment) is beyond the last section")
                                return
                            }
                        }

                        let itemIndex = i - offset

                        var (date, items) = sections[currentSectionIndex]
                        guard itemIndex < items.count else {
                            offset += items.count
                            currentSectionIndex += 1
                            // Start over in the next section.
                            return tryAddNewItem()
                        }

                        guard !self.deletedAttachmentIds.contains(attachment.uniqueId) else {
                            owsFailDebug("\(attachment) has already been deleted; should not have been fetched.")
                            return
                        }

                        if let loadedItem = items[itemIndex] {
                            owsAssert(loadedItem.attachmentStream.uniqueId == attachment.uniqueId)
                            return
                        }

                        guard let item: MediaGalleryItem = self.buildGalleryItem(attachment: attachment,
                                                                                 transaction: transaction) else {
                            owsFailDebug("unexpectedly failed to buildGalleryItem")
                            return
                        }

                        owsAssertDebug(item.galleryDate == date,
                                       "item from \(item.galleryDate) put into section for \(date)")
                        // Performance hack: clear out the current 'items' array in 'sections' to avoid copy-on-write.
                        sections.replace(key: date, value: [])
                        items[itemIndex] = item
                        sections.replace(key: date, value: items)
                    }

                    tryAddNewItem()
                }
            }
        }

        if let completionBlock = completion {
            let firstNewLaterSectionIndex = sections.count - numNewlyLoadedLaterSections
            var newlyLoadedSections = IndexSet()
            newlyLoadedSections.insert(integersIn: 0..<numNewlyLoadedEarlierSections)
            newlyLoadedSections.insert(integersIn: firstNewLaterSectionIndex..<sections.count)
            completionBlock(newlyLoadedSections)
        }
    }

    private func ensureGalleryItemsLoaded(_ direction: GalleryDirection,
                                          item: MediaGalleryItem,
                                          amount: Int,
                                          shouldLoadAlbumRemainder: Bool) {
        guard let path = indexPath(for: item) else {
            owsFail("showing detail view for an item that hasn't been loaded: \(item.attachmentStream)")
        }

        ensureGalleryItemsLoaded(direction,
                                 sectionIndex: path.section,
                                 itemIndex: path.item,
                                 amount: amount,
                                 shouldLoadAlbumRemainder: shouldLoadAlbumRemainder)
    }

    internal func ensureLoadedForDetailView(focusedAttachment: TSAttachment) -> MediaGalleryItem? {
        let newItem: MediaGalleryItem? = databaseStorage.uiRead { transaction in
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
                let count = numberOfItemsInSection(for: focusedItem.galleryDate, transaction: transaction)
                var items: [MediaGalleryItem?] = Array(repeating: nil, count: count)
                items[offsetInSection] = focusedItem
                sections.append(key: focusedItem.galleryDate, value: items)
                return focusedItem
            }

            // Assume we've set up this section, but may or may not have initialized the item.
            guard var items = sections[focusedItem.galleryDate] else {
                owsFailDebug("section for focused item not found")
                return nil
            }

            if let existingItem = items[safe: offsetInSection] ?? nil {
                return existingItem
            }

            // Swap out the section items to avoid copy-on-write.
            sections.replace(key: focusedItem.galleryDate, value: [])
            items[offsetInSection] = focusedItem
            sections.replace(key: focusedItem.galleryDate, value: items)
            return focusedItem
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

    private func numberOfItemsInSection(for date: GalleryDate, transaction: SDSAnyReadTransaction) -> Int {
        return Int(mediaGalleryFinder.mediaCount(in: date.interval,
                                                 excluding: deletedAttachmentIds,
                                                 transaction: transaction.unwrapGrdbRead))
    }

    /// Loads at least one section before the oldest section, though not any of the items in it.
    ///
    /// Operates in bulk in an attempt to cut down on database traffic, meaning it may measure multiple sections at once.
    ///
    /// Returns the number of new sections loaded, which can be used to update section indexes.
    internal func loadEarlierSections(batchSize: Int, transaction: SDSAnyReadTransaction) -> Int {
        guard !hasFetchedOldest else {
            return 0
        }

        var newSectionCounts: [GalleryDate: Int] = [:]
        let earliestDate = sections.orderedKeys.first?.interval.start ?? .distantFutureForMillisecondTimestamp

        var newEarliestDate: GalleryDate?
        let result = mediaGalleryFinder.enumerateTimestamps(before: earliestDate,
                                                            excluding: deletedAttachmentIds,
                                                            count: batchSize,
                                                            transaction: transaction.unwrapGrdbRead) { timestamp in
            let galleryDate = GalleryDate(date: timestamp)
            newSectionCounts[galleryDate, default: 0] += 1
            owsAssertDebug(newEarliestDate == nil || galleryDate <= newEarliestDate!,
                           "expects timestamps to be fetched in descending order")
            newEarliestDate = galleryDate
        }

        if result == .reachedEnd {
            hasFetchedOldest = true
        } else {
            // Make sure we have the full count for the earliest loaded section.
            newSectionCounts[newEarliestDate!] = numberOfItemsInSection(for: newEarliestDate!,
                                                                        transaction: transaction)
        }

        if sections.isEmpty {
            hasFetchedMostRecent = true
        }

        let sortedDates = newSectionCounts.keys.sorted()
        owsAssertDebug(sections.isEmpty || sortedDates.isEmpty || sortedDates.last! < sections.orderedKeys.first!)
        for date in sortedDates.reversed() {
            sections.prepend(key: date, value: Array(repeating: nil, count: newSectionCounts[date]!))
        }
        return sortedDates.count
    }

    /// Loads at least one section after the latest section, though not any of the items in it.
    ///
    /// Operates in bulk in an attempt to cut down on database traffic, meaning it may measure multiple sections at once.
    ///
    /// Returns the number of new sections loaded.
    internal func loadLaterSections(batchSize: Int, transaction: SDSAnyReadTransaction) -> Int {
        guard !hasFetchedMostRecent else {
            return 0
        }

        var newSectionCounts: [GalleryDate: Int] = [:]
        let latestDate = sections.orderedKeys.last?.interval.end ?? Date(millisecondsSince1970: 0)

        var newLatestDate: GalleryDate?
        let result = mediaGalleryFinder.enumerateTimestamps(after: latestDate,
                                                            excluding: deletedAttachmentIds,
                                                            count: batchSize,
                                                            transaction: transaction.unwrapGrdbRead) { timestamp in
            let galleryDate = GalleryDate(date: timestamp)
            newSectionCounts[galleryDate, default: 0] += 1
            owsAssertDebug(newLatestDate == nil || newLatestDate! <= galleryDate,
                           "expects timestamps to be fetched in ascending order")
            newLatestDate = galleryDate
        }

        if result == .reachedEnd {
            hasFetchedMostRecent = true
        } else {
            // Make sure we have the full count for the latest loaded section.
            newSectionCounts[newLatestDate!] = numberOfItemsInSection(for: newLatestDate!,
                                                                      transaction: transaction)
        }

        if sections.isEmpty {
            hasFetchedOldest = true
        }

        let sortedDates = newSectionCounts.keys.sorted()
        owsAssertDebug(sections.isEmpty || sortedDates.isEmpty || sections.orderedKeys.last! < sortedDates.first!)
        for date in sortedDates {
            sections.append(key: date, value: Array(repeating: nil, count: newSectionCounts[date]!))
        }
        return sortedDates.count
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
                for item in items {
                    let message = item.message
                    let attachment = item.attachmentStream
                    message.removeAttachment(attachment, transaction: transaction)
                    if message.attachmentIds.count == 0 {
                        Logger.debug("removing message after removing last media attachment")
                        message.anyRemove(transaction: transaction)
                    }
                }

                transaction.addAsyncCompletion {
                    self.deletedAttachmentIds.subtract(items.lazy.map { $0.attachmentStream.uniqueId })
                }
            }
        }

        var deletedIndexPaths: [IndexPath]
        if let indexPaths = givenIndexPaths {
            deletedIndexPaths = indexPaths
        } else {
            deletedIndexPaths = items.compactMap { indexPath(for: $0) }
            owsAssertDebug(deletedIndexPaths.count == items.count, "removing an item that wasn't loaded")
        }
        deletedIndexPaths.sort()

        var deletedSections: IndexSet = IndexSet()
        let deletedItemsForChecking = Set(items)

        // Iterate in reverse so the index paths don't get disrupted.
        for path in deletedIndexPaths.reversed() {
            let sectionKey = self.sections.orderedKeys[path.section]
            // Swap out / swap in to avoid copy-on-write.
            var section = self.sections.replace(key: sectionKey, value: [])

            if let removedItem = section.remove(at: path.item) {
                owsAssertDebug(deletedItemsForChecking.contains(removedItem), "removed the wrong item")
            } else {
                owsFailDebug("removed an item that wasn't loaded, which can't be correct")
            }

            if section.isEmpty {
                self.sections.remove(at: path.section)
                deletedSections.insert(path.section)
            } else {
                self.sections.replace(key: sectionKey, value: section)
            }
        }

        isCurrentlyProcessingExternalDeletion = false

        delegates.forEach { $0.mediaGallery(self, deletedSections: deletedSections, deletedItems: deletedIndexPaths) }
    }

    // MARK: -

    /// Searches the appropriate section for this item.
    internal func indexPath(for item: MediaGalleryItem) -> IndexPath? {
        // Search backwards because people view recent items.
        // Note: we could use binary search because orderedKeys is sorted.
        guard let sectionIndex = sections.orderedKeys.lastIndex(of: item.galleryDate),
              let itemIndex = sections[sectionIndex].value.lastIndex(of: item) else {
            return nil
        }

        return IndexPath(item: itemIndex, section: sectionIndex)
    }

    /// Returns the path to the next item after `path` (ignoring sections).
    ///
    /// If `path` refers to the last item in the gallery, returns `nil`.
    private func indexPath(after path: IndexPath) -> IndexPath? {
        owsAssert(path.count == 2)
        var result = path

        // Next item?
        result.item += 1
        if result.item < sections[result.section].value.count {
            return result
        }

        // Next section?
        result.item = 0
        result.section += 1
        if result.section < sections.count {
            owsAssertDebug(!sections[result.section].value.isEmpty, "no empty sections")
            return result
        }

        // Reached the end.
        return nil
    }

    /// Returns the path to the item just before `path` (ignoring sections).
    ///
    /// If `path` refers to the first item in the gallery, returns `nil`.
    private func indexPath(before path: IndexPath) -> IndexPath? {
        owsAssert(path.count == 2)
        var result = path

        // Previous item?
        if result.item > 0 {
            result.item -= 1
            return result
        }

        // Previous section?
        if result.section > 0 {
            result.section -= 1
            owsAssertDebug(!sections[result.section].value.isEmpty, "no empty sections")
            result.item = sections[result.section].value.count - 1
            return result
        }

        // Reached the start.
        return nil
    }

    /// Returns the item at `path`, which will be `nil` if not yet loaded.
    ///
    /// `path` must be a valid path for the items currently loaded.
    internal func galleryItem(at path: IndexPath) -> MediaGalleryItem? {
        owsAssert(path.count == 2)
        guard let validItem: MediaGalleryItem? = sections[safe: path.section]?.value[safe: path.item] else {
            owsFailDebug("invalid path")
            return nil
        }
        // The result might still be nil if the item hasn't been loaded.
        return validItem
    }

    private let kGallerySwipeLoadBatchSize: Int = 5

    internal func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("")

        if !isCurrentlyProcessingExternalDeletion {
            self.ensureGalleryItemsLoaded(.after,
                                          item: currentItem,
                                          amount: kGallerySwipeLoadBatchSize,
                                          shouldLoadAlbumRemainder: true)
        }

        guard let currentPath = indexPath(for: currentItem) else {
            owsFailDebug("current item not found")
            return nil
        }

        // Repeatedly calling indexPath(after:) isn't super efficient,
        // but we don't expect it to be more than a few steps.
        let laterItemPaths = sequence(first: currentPath, next: { self.indexPath(after: $0) }).dropFirst()
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

    internal func galleryItem(before currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("")

        if !isCurrentlyProcessingExternalDeletion {
            self.ensureGalleryItemsLoaded(.before,
                                          item: currentItem,
                                          amount: kGallerySwipeLoadBatchSize,
                                          shouldLoadAlbumRemainder: true)
        }

        guard let currentPath = indexPath(for: currentItem) else {
            owsFailDebug("current item not found")
            return nil
        }

        // Repeatedly calling indexPath(before:) isn't super efficient,
        // but we don't expect it to be more than a few steps.
        let olderItemPaths = sequence(first: currentPath, next: { self.indexPath(before: $0) }).dropFirst()
        for previousPath in olderItemPaths {
            guard let loadedPreviousItem = galleryItem(at: previousPath) else {
                owsAssertDebug(isCurrentlyProcessingExternalDeletion,
                               "should have loaded the previous item already")
                return nil
            }

            if !deletedGalleryItems.contains(loadedPreviousItem) {
                return loadedPreviousItem
            }
        }

        // already at first item
        return nil
    }

    internal var galleryItemCount: Int {
        return databaseStorage.uiRead { transaction in
            return Int(mediaGalleryFinder.mediaCount(excluding: deletedAttachmentIds,
                                                     transaction: transaction.unwrapGrdbRead))
        }
    }
}

extension MediaGallery: UIDatabaseSnapshotDelegate {

    func uiDatabaseSnapshotWillUpdate() {
        // no-op
    }

    func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        // Process deletions before insertions,
        // because we can modify our existing model for deletions but have to reset with insertions.
        process(deletedAttachmentIds: databaseChanges.attachmentDeletedUniqueIds)
        process(newAttachmentIds: databaseChanges.attachmentUniqueIds)
    }

    func uiDatabaseSnapshotDidUpdateExternally() {
        // no-op
    }

    func uiDatabaseSnapshotDidReset() {
        // no-op
    }
}
