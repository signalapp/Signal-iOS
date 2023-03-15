//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

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
        self.galleryDate = GalleryDate(message: message)
        self.albumIndex = message.attachmentIds.firstIndex(of: attachmentStream.uniqueId) ?? 0
        self.orderingKey = MediaGalleryItemOrderingKey(messageSortKey: message.sortId, attachmentSortKey: albumIndex)
        if let captionText = attachmentStream.caption?.filterForDisplay {
            self.captionForDisplay = captionText
        } else {
            self.captionForDisplay = message.body?.filterForDisplay
        }
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
    func mediaGalleryDidDeleteItem(_ mediaGallery: MediaGallery)

    func mediaGalleryDidReloadItems(_ mediaGallery: MediaGallery)
    /// `mediaGallery` has added one or more new sections at the end.
    func didAddSectionInMediaGallery(_ mediaGallery: MediaGallery)
    func didReloadAllSectionsInMediaGallery(_ mediaGallery: MediaGallery)

    /// Clients must implement this if they care about journal processing. They should do something like this:
    ///
    ///     func mediaGallery(_ mediaGallery: MediaGallery, applyUpdate update: MediaGallery.Update) {
    ///         self?.collectionView.performBatchUpdates {
    ///             let (journal, userData) = update.commit()
    ///             self?.handleJournal(journal, userData)
    ///         }
    ///     }
    ///
    /// Note that because UICollectionView wants you to call `performBatchUpdates` before the data
    /// model changes and `update.commit()` causes the snapshot to change, you'll want to be sure
    /// to order them as shown above.
    ///
    /// Once the update is committed, no further delegates will be asked to apply the update.
    ///
    /// If an attempted mutation had no effects, applyUpdate will not be called.
    func mediaGallery(_ mediaGallery: MediaGallery, applyUpdate update: MediaGallery.Update)
}

/// A value that is associated with each mutation of MediaGallerySections.
struct MediaGalleryUpdateUserData {
    /// If enabled, animations will be disabled for the batch update. Other mutations that ended up in the journal will also get their animations disabled if any user
    /// data in the update has this set to true.
    var disableAnimations = false

    /// Set to true when inserts to the top should not cause a scroll.
    var shouldRecordContentSizeBeforeInsertingToTop = false
}

/// A backing store for media views (page-based or tile-based)
///
/// MediaGallery models a list of GalleryDate-based sections, each of which has a certain number of items.
/// Sections are loaded on demand (that is, there may be newer and older sections that are not in the model), and always
/// know their number of items. Items are also loaded on demand, potentially non-contiguously.
///
/// This model is designed around the needs of UICollectionView, but it also supports flat views of media.
class MediaGallery: Dependencies {
    typealias Sections = MediaGallerySections<Loader, MediaGalleryUpdateUserData>
    typealias Update = Sections.Update
    typealias Journal = [JournalingOrderedDictionaryChange<Sections.ItemChange>]
    typealias MediaType = MediaGalleryFinder.MediaType

    // Used for filtering.
    private(set) var allowedMediaType: MediaType?

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

    private var mediaGalleryFinder: MediaGalleryFinder
    private var sections: Sections!

    deinit {
        Logger.debug("")
    }

    @objc
    init(thread: TSThread) {
        let finder = MediaGalleryFinder(thread: thread, allowedMediaType: nil)
        self.mediaGalleryFinder = finder
        self.sections = MediaGallerySections(loader: Loader(mediaGallery: self, finder: finder))
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

    /// Provides access to a mutable instance of `sections`, ensuring that the journal is processed after the closure returns.
    ///
    /// This is useful because:
    ///   - It makes the locations of changes easy to find.
    ///   - It ensures self.performBatchUpdates is called before the snapshot of the data model changes.
    ///   - It ensures the journal is processed for all mutations.
    private func mutate<T>(_ closure: (inout Sections) -> T) -> T {
        let result = closure(&self.sections)
        applyPendingUpdate()
        return result
    }

    /// Runs closure immediately but it can complete asynchronously.
    ///
    /// - Parameters:
    ///   - closure: A closure that is run immediately which begins an async mutation on `MediaGallerySections`.
    ///     - sections: A mutable instance of `MediaGallerySections`.
    ///     - callback: When the async mutation completes, the caller must invoke `callback` exactly once.
    ///   - completion: This is called after journal processing subsequent to the completion of the async operation is finished.
    private func mutateAsync<T>(_ closure: (_ sections: inout Sections,
                                            _ callback: @escaping (T) -> Void) -> Void,
                                completion: @escaping (T) -> Void) {
        closure(&self.sections) { [weak self] result in
            guard let self else { return }
            self.applyPendingUpdate()
            completion(result)
        }
    }

    private func applyPendingUpdate() {
        let pendingUpdate = sections.takePendingUpdate()
        for delegate in delegates {
            guard !pendingUpdate.hasBeenCommitted else {
                break
            }
            delegate.mediaGallery(self, applyUpdate: pendingUpdate)
        }
        if !pendingUpdate.hasBeenCommitted {
            _ = pendingUpdate.commit()
        }
    }

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

        mutate { sections in
            _ = sections.reloadSections(for: sectionsNeedingUpdate)
        }
        delegates.forEach {
            $0.mediaGalleryDidReloadItems(self)
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

        let dates = relevantAttachments.lazy.map {
            GalleryDate(date: Date(millisecondsSince1970: $0.timestamp))
        }
        let newAttachmentResult = mutate { sections in
            sections.handleNewAttachments(dates)
        }
        if newAttachmentResult.didReset {
            delegates.forEach { $0.didReloadAllSectionsInMediaGallery(self) }
        } else {
            if !newAttachmentResult.update.isEmpty {
                delegates.forEach { $0.mediaGalleryDidReloadItems(self) }
            }
            if newAttachmentResult.didAddAtEnd {
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
        let startOfAlbum = section[..<itemPath.item].suffix { $0.item?.message.uniqueId == item.message.uniqueId }.startIndex
        let endOfAlbum = section[itemPath.item...].prefix { $0.item?.message.uniqueId == item.message.uniqueId }.endIndex
        let items = section[startOfAlbum..<endOfAlbum].map { $0.item! }

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
                                           async: Bool = false,
                                           userData: MediaGalleryUpdateUserData? = nil,
                                           completion: ((_ newSections: IndexSet) -> Void)? = nil) {
        Logger.info("")
        let anchorItem: MediaGalleryItem? = sections.loadedItem(at: MediaGalleryIndexPath(item: itemIndex, section: sectionIndex))

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

        if async {
            Logger.info("will ensure loaded asynchronously")
            mutateAsync { sections, callback in
                sections.asyncEnsureItemsLoaded(in: naiveRequestRange,
                                                relativeToSection: sectionIndex,
                                                userData: userData) { newlyLoadedSections in
                    callback(newlyLoadedSections)
                }
            } completion: { newlyLoadedSections in
                completion?(newlyLoadedSections)
            }
        } else {
            Logger.info("will ensure loaded synchronously")
            let newlyLoadedSections = mutate { sections in
                sections.ensureItemsLoaded(in: naiveRequestRange,
                                           relativeToSection: sectionIndex,
                                           userData: userData)
            }
            completion?(newlyLoadedSections)
        }
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
        Logger.info("")
        let newItem: MediaGalleryItem? = databaseStorage.read { transaction -> MediaGalleryItem? in
            guard let focusedItem = buildGalleryItem(attachment: focusedAttachment, transaction: transaction) else {
                return nil
            }

            guard let rowid = mediaGalleryFinder.rowid(of: focusedItem.attachmentStream,
                                                       in: focusedItem.galleryDate.interval,
                                                       excluding: deletedAttachmentIds,
                                                       transaction: transaction.unwrapGrdbRead) else {
                // The item may have just been deleted.
                Logger.warn("showing detail for item not in the database")
                return nil
            }

            return mutate { sections in
                if sections.isEmpty {
                    // Set up the current section only.
                    return sections.loadInitialSection(for: focusedItem.galleryDate,
                                                       replacement: (item: focusedItem,
                                                                     rowid: rowid),
                                                       transaction: transaction)
                } else {
                    return sections.getOrReplaceItem(focusedItem, rowid: rowid)
                }
            }
        }

        guard let focusedItem = newItem else {
            return nil
        }

        // For a speedy load, we only fetch a few items on either side of
        // the initial message
        Logger.info("ensureGalleryItemsLoaded: will call")
        ensureGalleryItemsLoaded(.around,
                                 item: focusedItem,
                                 amount: kGallerySwipeLoadBatchSize * 2,
                                 shouldLoadAlbumRemainder: true)
        Logger.info("ensureGalleryItemsLoaded: finished")

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
    internal func loadEarlierSections(batchSize: Int, userData: MediaGalleryUpdateUserData? = nil) -> Int {
        return mutate { sections in
            sections.loadEarlierSections(batchSize: batchSize, userData: userData)
        }
    }

    internal func asyncLoadEarlierSections(batchSize: Int,
                                           highPriority: Bool,
                                           userData: MediaGalleryUpdateUserData? = nil,
                                           completion: ((Int) -> Void)?) {
        mutateAsync { sections, callback in
            sections.asyncLoadEarlierSections(batchSize: batchSize,
                                              highPriority: highPriority,
                                              userData: userData,
                                              completion: callback)
        } completion: { numberOfSectionsLoaded in
            completion?(numberOfSectionsLoaded)
        }
    }

    /// Loads at least one section after the latest section, though not any of the items in it.
    ///
    /// Operates in bulk in an attempt to cut down on database traffic, meaning it may measure multiple sections at once.
    ///
    /// Returns the number of new sections loaded.
    internal func loadLaterSections(batchSize: Int, userData: MediaGalleryUpdateUserData? = nil) -> Int {
        return mutate { sections in
            sections.loadLaterSections(batchSize: batchSize, userData: userData)
        }
    }

    internal func asyncLoadLaterSections(batchSize: Int,
                                         userData: MediaGalleryUpdateUserData? = nil,
                                         completion: ((Int) -> Void)?) {
        mutateAsync { sections, callback in
            sections.asyncLoadLaterSections(batchSize: batchSize, userData: userData, completion: callback)
        } completion: { numberOfSectionsLoaded in
            completion?(numberOfSectionsLoaded)
        }

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
                         atIndexPaths givenIndexPaths: [MediaGalleryIndexPath]? = nil,
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

        var deletedIndexPaths: [MediaGalleryIndexPath]
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

        _ = mutate { sections in
            sections.removeLoadedItems(atIndexPaths: deletedIndexPaths)
        }

        delegates.forEach { $0.mediaGalleryDidDeleteItem(self) }
    }

    // MARK: -

    /// Searches the appropriate section for this item.
    ///
    /// Will return nil if the item was not loaded through the gallery.
    internal func indexPath(for item: MediaGalleryItem) -> MediaGalleryIndexPath? {
        return sections.indexPath(for: item)
    }

    /// Returns the item at `path`, which will be `nil` if not yet loaded.
    ///
    /// `path` must be a valid path for the items currently loaded.
    internal func galleryItem(at path: MediaGalleryIndexPath) -> MediaGalleryItem? {
        return sections.loadedItem(at: path)
    }

    internal func galleryItemWithoutLoading(at path: MediaGalleryIndexPath) -> MediaGalleryItem? {
        return sections.itemsBySection[path.section].value[path.item].item
    }

    /// Change what media is filtered out.
    ///
    /// - Parameters:
    ///   - allowedMediaType: If `nil`, do not filter results. Otherwise, show only media of this type.
    ///   - loadUntil: Load sections from the latest until this date, inclusive.
    ///   - batchSize: Number of items to load at once.
    func setAllowedMediaType(_ allowedMediaType: MediaType?, loadUntil: GalleryDate, batchSize: Int, firstVisibleIndexPath: MediaGalleryIndexPath?) -> MediaGalleryIndexPath? {
        self.allowedMediaType = allowedMediaType
        return mutate { sections in
            mediaGalleryFinder = MediaGalleryFinder(thread: mediaGalleryFinder.thread,
                                                    allowedMediaType: allowedMediaType)
            let newLoader = Loader(mediaGallery: self, finder: mediaGalleryFinder)
            return sections.replaceLoader(loader: newLoader,
                                          batchSize: batchSize,
                                          loadUntil: loadUntil,
                                          searchFor: firstVisibleIndexPath)
        }
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
        let advance: (MediaGalleryIndexPath) -> MediaGalleryIndexPath?
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
}

extension MediaGallery: DatabaseChangeDelegate {

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        // Ignore: we get local changes from notifications instead.
    }

    func databaseChangesDidUpdateExternally() {
        // Conservatively assume anything could have happened.
        mutate { sections in
            sections.reset()
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

        fileprivate weak var mediaGallery: MediaGallery?
        fileprivate let finder: MediaGalleryFinder

        func rowIdsAndDatesOfItemsInSection(for date: GalleryDate,
                                            offset: Int,
                                            ascending: Bool,
                                            transaction: SDSAnyReadTransaction) -> [RowIdAndDate] {
            guard let mediaGallery else {
                return []
            }
            return finder.rowIdsAndDates(in: date.interval,
                                         excluding: mediaGallery.deletedAttachmentIds,
                                         offset: offset,
                                         ascending: ascending,
                                         transaction: transaction.unwrapGrdbRead)
        }

        func enumerateTimestamps(before date: Date,
                                 count: Int,
                                 transaction: SDSAnyReadTransaction,
                                 block: (Date, Int64) -> Void) -> EnumerationCompletion {
            guard let mediaGallery else {
                return .reachedEnd
            }
            return finder.enumerateTimestamps(before: date,
                                              excluding: mediaGallery.deletedAttachmentIds,
                                              count: count,
                                              transaction: transaction.unwrapGrdbRead,
                                              block: block)
        }

        func enumerateTimestamps(after date: Date,
                                 count: Int,
                                 transaction: SDSAnyReadTransaction,
                                 block: (Date, Int64) -> Void) -> EnumerationCompletion {
            guard let mediaGallery else {
                return .reachedEnd
            }
            return finder.enumerateTimestamps(after: date,
                                              excluding: mediaGallery.deletedAttachmentIds,
                                              count: count,
                                              transaction: transaction.unwrapGrdbRead,
                                              block: block)
        }

        func enumerateItems(in interval: DateInterval,
                            range: Range<Int>,
                            transaction: SDSAnyReadTransaction,
                            block: (_ offset: Int, _ uniqueId: String, _ buildItem: () -> MediaGalleryItem) -> Void) {
            guard let mediaGallery else {
                return
            }
            finder.enumerateMediaAttachments(
                in: interval,
                excluding: mediaGallery.deletedAttachmentIds,
                range: NSRange(range),
                transaction: transaction.unwrapGrdbRead
            ) { offset, attachment in
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
