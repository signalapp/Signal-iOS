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
        self.init(date: date)
    }

    init(date: Date) {
        self.year = Calendar.current.component(.year, from: date)
        self.month = Calendar.current.component(.month, from: date)
    }

    init(year: Int, month: Int) {
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

    public var asInterval: DateInterval {
        return Calendar.current.dateInterval(of: .month, for: date)!
    }

    private var isThisYear: Bool {
        let now = Date()
        let thisYear = Calendar.current.component(.year, from: now)

        return self.year == thisYear
    }

    static let thisYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    static let olderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
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

    func mediaGallery(_ mediaGallery: MediaGallery, didReloadItemsInSections sections: IndexSet)
}

class MediaGallery {

    // MARK: - Dependencies

    private var audioPlayer: CVAudioPlayer {
        return AppEnvironment.shared.audioPlayer
    }

    // MARK: -

    var deletedAttachmentIds: Set<String> = Set()
    var deletedGalleryItems: Set<MediaGalleryItem> = Set()
    var isCurrentlyProcessingExternalDeletion = false

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

    func process(deletedAttachmentIds incomingDeletedAttachmentIds: Set<String>) {
        let newlyDeletedAttachmentIds = incomingDeletedAttachmentIds.subtracting(deletedAttachmentIds)
        if newlyDeletedAttachmentIds.isEmpty {
            return
        }

        let allItems = sections.lazy.map { $0.value }.joined()
        let deletedItems: [MediaGalleryItem] = newlyDeletedAttachmentIds.compactMap { attachmentId in
            // FIXME: extremely slow repeated linear search
            guard let deletedItem = allItems.first(where: { galleryItem in
                galleryItem?.attachmentStream.uniqueId == attachmentId
            }) else {
                Logger.debug("deletedItem was never loaded - no need to remove.")
                return nil
            }

            return deletedItem
        }

        delete(items: deletedItems, initiatedBy: self, deleteFromDB: false)
    }

    func process(newAttachmentIds: Set<String>) {
        if newAttachmentIds.isEmpty {
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

    func ensureGalleryItemsLoaded(_ direction: GalleryDirection,
                                  sectionIndex: Int,
                                  itemIndex: Int,
                                  amount: UInt,
                                  shouldLoadAlbumRemainder: Bool,
                                  completion: ((_ newSections: IndexSet) -> Void)? = nil) {
        if isCurrentlyProcessingExternalDeletion {
            owsFailDebug("cannot access database while model is being updated")
            return
        }

        var numNewlyLoadedEarlierSections: Int = 0
        var numNewlyLoadedLaterSections: Int = 0

        Bench(title: "fetching gallery items") {
            self.databaseStorage.uiRead { transaction in
                var requestRange: NSRange = {
                    var range: Range<Int> = {
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

                    if shouldLoadAlbumRemainder, let item = sections[sectionIndex].value[safe: itemIndex] ?? nil {
                        let albumStart = (itemIndex - item.albumIndex)
                        let albumEnd = albumStart + item.message.attachmentIds.count
                        range = (min(range.lowerBound, albumStart)..<max(range.upperBound, albumEnd))
                    }

                    return NSRange(range)
                }()

                // Figure out the earliest section this request will cross.
                var currentSectionIndex = sectionIndex
                while requestRange.location < 0 {
                    if currentSectionIndex == 0 {
                        let newlyLoadedCount = loadEarlierSections(transaction: transaction)
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
                let interval = DateInterval(start: sections.orderedKeys[currentSectionIndex].date,
                                            end: .distantFutureForMillisecondTimestamp)

                let finder = mediaGalleryFinder.grdbAdapter
                var offset = 0
                finder.enumerateMediaAttachments(in: interval,
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
                            numNewlyLoadedLaterSections += loadLaterSections(transaction: transaction)
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

    func ensureGalleryItemsLoaded(_ direction: GalleryDirection,
                                  item: MediaGalleryItem,
                                  amount: UInt,
                                  shouldLoadAlbumRemainder: Bool,
                                  completion: ((_ newSections: IndexSet) -> Void)? = nil) {
        guard let sectionIndex = sections.orderedKeys.firstIndex(of: item.galleryDate),
              let itemIndex = sections[sectionIndex].value.firstIndex(of: item) else {
            owsFail("showing detail view for an item that hasn't been loaded: \(item.attachmentStream)")
        }

        ensureGalleryItemsLoaded(direction,
                                 sectionIndex: sectionIndex,
                                 itemIndex: itemIndex,
                                 amount: amount,
                                 shouldLoadAlbumRemainder: shouldLoadAlbumRemainder,
                                 completion: completion)
    }

    public func ensureLoadedForDetailView(focusedAttachment: TSAttachment) -> MediaGalleryItem? {
        let newItem: MediaGalleryItem? = databaseStorage.uiRead { transaction in
            guard let focusedItem = buildGalleryItem(attachment: focusedAttachment, transaction: transaction) else {
                return nil
            }

            let finder = mediaGalleryFinder.grdbAdapter
            guard let offsetInSection = finder.mediaIndex(of: focusedItem.attachmentStream,
                                                          in: focusedItem.galleryDate.asInterval,
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
        ensureGalleryItemsLoaded(.around, item: focusedItem, amount: 10, shouldLoadAlbumRemainder: true)

        return focusedItem
    }

    // MARK: - Section-based API

    private func numberOfItemsInSection(for date: GalleryDate, transaction: SDSAnyReadTransaction) -> Int {
        return Int(mediaGalleryFinder.grdbAdapter.mediaCount(in: date.asInterval,
                                                             excluding: deletedAttachmentIds,
                                                             transaction: transaction.unwrapGrdbRead))
    }

    func loadEarlierSections(transaction: SDSAnyReadTransaction) -> Int {
        if hasFetchedOldest {
            return 0
        }

        var newSectionCounts: [GalleryDate: Int] = [:]
        let earliestDate = sections.orderedKeys.first?.date ?? .distantFutureForMillisecondTimestamp

        var newEarliestDate: GalleryDate? = nil
        let finder = self.mediaGalleryFinder.grdbAdapter
        let result = finder.enumerateTimestamps(before: earliestDate,
                                                excluding: deletedAttachmentIds,
                                                count: 50,
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

        let sortedDates = newSectionCounts.keys.sorted()
        owsAssertDebug(sections.isEmpty || sortedDates.isEmpty || sortedDates.last! < sections.orderedKeys.first!)
        for date in sortedDates.reversed() {
            sections.prepend(key: date, value: Array(repeating: nil, count: newSectionCounts[date]!))
        }
        return sortedDates.count
    }

    func loadLaterSections(transaction: SDSAnyReadTransaction) -> Int {
        if hasFetchedMostRecent {
            return 0
        }

        var newSectionCounts: [GalleryDate: Int] = [:]
        let latestDate = sections.orderedKeys.last?.asInterval.end ?? Date(millisecondsSince1970: 0)

        var newLatestDate: GalleryDate? = nil
        let finder = self.mediaGalleryFinder.grdbAdapter
        let result = finder.enumerateTimestamps(after: latestDate,
                                                excluding: deletedAttachmentIds,
                                                count: 50,
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

        let sortedDates = newSectionCounts.keys.sorted()
        owsAssertDebug(sections.isEmpty || sortedDates.isEmpty || sections.orderedKeys.last! < sortedDates.first!)
        for date in sortedDates {
            sections.append(key: date, value: Array(repeating: nil, count: newSectionCounts[date]!))
        }
        return sortedDates.count
    }

    // MARK: -

    private var _delegates: [Weak<MediaGalleryDelegate>] = []

    var delegates: [MediaGalleryDelegate] {
        return _delegates.compactMap { $0.value }
    }

    func addDelegate(_ delegate: MediaGalleryDelegate) {
        _delegates = _delegates.filter({ $0.value != nil}) + [Weak(value: delegate)]
    }

    func delete(items: [MediaGalleryItem],
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

                transaction.addSyncCompletion {
                    self.deletedAttachmentIds.subtract(items.lazy.map { $0.attachmentStream.uniqueId })
                }
            }
        }

        var deletedIndexPaths: [IndexPath]
        if let indexPaths = givenIndexPaths {
            deletedIndexPaths = indexPaths
        } else {
            deletedIndexPaths = []
            deletedIndexPaths.reserveCapacity(items.count)
            for item in items {
                guard let sectionIndex = self.sections.orderedKeys.firstIndex(of: item.galleryDate) else {
                    owsFailDebug("item with unknown date")
                    return
                }

                guard let itemIndex = self.sections[sectionIndex].value.firstIndex(of: item) else {
                    owsFailDebug("item was never loaded")
                    return
                }

                deletedIndexPaths.append(IndexPath(item: itemIndex, section: sectionIndex))
            }
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

    let kGallerySwipeLoadBatchSize: UInt = 5

    internal func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("")

        if !isCurrentlyProcessingExternalDeletion {
            self.ensureGalleryItemsLoaded(.after,
                                          item: currentItem,
                                          amount: kGallerySwipeLoadBatchSize,
                                          shouldLoadAlbumRemainder: true)
        }

        let allItems = sections.lazy.map { $0.value }.joined()

        // FIXME: This doesn't need to start searching from the start.
        guard let currentIndex = allItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        for nextItem in allItems[currentIndex...].dropFirst() {
            guard let loadedNextItem = nextItem else {
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

        let allItems = sections.lazy.map { $0.value }.joined()

        // FIXME: This doesn't need to start searching from the start.
        guard let currentIndex = allItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        for previousItem in allItems[..<currentIndex].reversed() {
            guard let loadedPreviousItem = previousItem else {
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

    var galleryItemCount: Int {
        let count: UInt = databaseStorage.uiRead { transaction in
            return self.mediaGalleryFinder.mediaCount(transaction: transaction)
        }
        return Int(count) - deletedAttachmentIds.count
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
