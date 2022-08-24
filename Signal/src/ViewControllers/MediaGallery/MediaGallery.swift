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
        guard let mediaGallery = self.mediaGallery else {
            owsFailDebug("mediaGallery was unexpectedly nil")
            return originalItems
        }

        return originalItems.filter { !mediaGallery.deletedGalleryItems.contains($0) }
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
    /// `mediaGallery` has added one or more new sections at the end.
    func didAddSectionInMediaGallery(_ mediaGallery: MediaGallery)
    func didReloadAllSectionsInMediaGallery(_ mediaGallery: MediaGallery)
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

    private let mediaGalleryFinder: MediaGalleryFinder
    private var sections: MediaGallerySections<Loader>!

    deinit {
        Logger.debug("")
    }

    @objc
    init(thread: TSThread) {
        self.mediaGalleryFinder = MediaGalleryFinder(thread: thread)
        self.sections = MediaGallerySections(loader: Loader(mediaGallery: self))
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(Self.newAttachmentsAvailable(_:)),
                                               name: MediaGalleryManager.newAttachmentsAvailableNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(Self.didRemoveAttachments(_:)),
                                               name: MediaGalleryManager.didRemoveAttachmentsNotification,
                                               object: nil)
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    // MARK: -

    @objc
    private func didRemoveAttachments(_ notification: Notification) {
        // Some of the deleted attachments may have been loaded and some may not.
        // Rather than try to identify which individual items should be removed from a section,
        // reload every section that was touched.
        // In some cases this may result in deleting sections entirely; we do this as a follow-up step so that
        // delegates don't get confused.
        AssertIsOnMainThread()
        let incomingDeletedAttachments = notification.object as! [MediaGalleryManager.ChangedAttachmentInfo]

        var sectionsNeedingUpdate = Set<GalleryDate>()
        for incomingDeletedAttachment in incomingDeletedAttachments {
            guard incomingDeletedAttachment.threadGrdbId == mediaGalleryFinder.threadId else {
                // This attachment is from a different thread.
                continue
            }
            guard deletedAttachmentIds.remove(incomingDeletedAttachment.uniqueId) == nil else {
                // This attachment was removed through MediaGallery and we already adjusted accordingly.
                continue
            }
            let sectionDate = GalleryDate(date: Date(millisecondsSince1970: incomingDeletedAttachment.timestamp))
            sectionsNeedingUpdate.insert(sectionDate)
        }

        guard !sectionsNeedingUpdate.isEmpty else {
            return
        }

        var sectionIndexesNeedingUpdate = IndexSet()
        var sectionsToDelete = IndexSet()

        databaseStorage.read { transaction in
            for sectionDate in sectionsNeedingUpdate {
                // Scan backwards; newer items are more likely to be modified.
                // (We could use a binary search here as well.)
                guard let sectionIndex = sections.sectionDates.lastIndex(of: sectionDate) else {
                    continue
                }

                // Refresh the section.
                let newCount = sections.reloadSection(for: sectionDate, transaction: transaction)

                sectionIndexesNeedingUpdate.insert(sectionIndex)
                if newCount == 0 {
                    sectionsToDelete.insert(sectionIndex)
                }
            }
        }
        delegates.forEach {
            $0.mediaGallery(self, didReloadItemsInSections: sectionIndexesNeedingUpdate)
        }

        guard !sectionsToDelete.isEmpty else {
            return
        }

        // Delete in reverse order so indexes are preserved as we go.
        sections.removeEmptySections(atIndexes: sectionsToDelete)
        delegates.forEach {
            $0.mediaGallery(self, deletedSections: sectionsToDelete, deletedItems: [])
        }
    }

    @objc
    private func newAttachmentsAvailable(_ notification: Notification) {
        AssertIsOnMainThread()
        let incomingNewAttachments = notification.object as! [MediaGalleryManager.ChangedAttachmentInfo]
        let relevantAttachments = incomingNewAttachments.filter { $0.threadGrdbId == mediaGalleryFinder.threadId }

        guard !relevantAttachments.isEmpty else {
            return
        }
        Logger.debug("")

        var sectionsNeedingUpdate = IndexSet()
        var didAddSectionAtEnd = false
        var didReset = false

        databaseStorage.read { transaction in
            for attachmentInfo in relevantAttachments {
                let sectionDate = GalleryDate(date: Date(millisecondsSince1970: attachmentInfo.timestamp))
                // Do a backwards search assuming new messages usually arrive at the end.
                // Still, this is kept sorted, so we ought to be able to do a binary search instead.
                if let lastSectionDate = sections.sectionDates.last, sectionDate > lastSectionDate {
                    // Only let clients know about the new section if they thought they were at the end;
                    // otherwise they'll fetch more if they need to.
                    if sections.hasFetchedMostRecent {
                        sections.resetHasFetchedMostRecent()
                        didAddSectionAtEnd = true
                    }
                } else if let sectionIndex = sections.sectionDates.lastIndex(of: sectionDate) {
                    sectionsNeedingUpdate.insert(sectionIndex)
                } else {
                    // We've loaded the first attachment in a new section that's not at the end. That can't be done
                    // transparently in MediaGallery's model, so let all our delegates know to refresh *everything*.
                    // This should be rare, but can happen if someone has automatic attachment downloading off and then
                    // goes back and downloads an attachment that crosses the month boundary.
                    sections.reset(transaction: transaction)
                    didReset = true
                    return
                }
            }

            for sectionIndex in sectionsNeedingUpdate {
                // Throw out everything in that section.
                let sectionDate = sections.sectionDates[sectionIndex]
                sections.reloadSection(for: sectionDate, transaction: transaction)
            }
        }

        if didReset {
            delegates.forEach { $0.didReloadAllSectionsInMediaGallery(self) }
        } else {
            if !sectionsNeedingUpdate.isEmpty {
                delegates.forEach { $0.mediaGallery(self, didReloadItemsInSections: sectionsNeedingUpdate) }
            }
            if didAddSectionAtEnd {
                delegates.forEach { $0.didAddSectionInMediaGallery(self) }
            }
        }
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
            // The item may have just been deleted.
            Logger.warn("message was unexpectedly nil")
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
                // The item may have just been deleted.
                Logger.warn("showing detail for item not in the database")
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
                         initiatedBy: AnyObject) {
        AssertIsOnMainThread()

        guard items.count > 0 else {
            return
        }

        Logger.info("with items: \(items.map { ($0.attachmentStream, $0.message.timestamp) })")

        deletedGalleryItems.formUnion(items)
        delegates.forEach { $0.mediaGallery(self, willDelete: items, initiatedBy: initiatedBy) }

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
            } catch {
                owsFailDebug("database error: \(error)")
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

        self.ensureGalleryItemsLoaded(direction,
                                      item: currentItem,
                                      amount: kGallerySwipeLoadBatchSize,
                                      shouldLoadAlbumRemainder: true)

        guard let currentPath = indexPath(for: currentItem) else {
            owsFailDebug("current item not found")
            return nil
        }

        // Repeatedly calling indexPath(before:) or indexPath(after:) isn't super efficient,
        // but we don't expect it to be more than a few steps.
        let laterItemPaths = sequence(first: currentPath, next: advance).dropFirst()
        for nextPath in laterItemPaths {
            guard let loadedNextItem = galleryItem(at: nextPath) else {
                owsFailDebug("should have loaded the next item already")
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
        // Ignore: we get local changes from notifications instead.
    }

    func databaseChangesDidUpdateExternally() {
        // Conservatively assume anything could have happened.
        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }
        delegates.forEach { $0.didReloadAllSectionsInMediaGallery(self) }
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
