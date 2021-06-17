//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum GalleryDirection {
    case before, after, around
}

class MediaGalleryAlbum {

    private var originalItems: [MediaGalleryItem]
    var items: [MediaGalleryItem] {
        get {
            guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
                owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
                return originalItems
            }

            return originalItems.filter { !mediaGalleryDataSource.deletedGalleryItems.contains($0) }
        }
    }

    weak var mediaGalleryDataSource: MediaGalleryDataSource?

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
        self.albumIndex = message.attachmentIds.index(of: attachmentStream.uniqueId!)
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

    // MARK: Equatable

    public static func == (lhs: MediaGalleryItem, rhs: MediaGalleryItem) -> Bool {
        return lhs.attachmentStream.uniqueId == rhs.attachmentStream.uniqueId
    }

    // MARK: Hashable

    public var hashValue: Int {
        return attachmentStream.uniqueId?.hashValue ?? attachmentStream.hashValue
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
        let date = message.dateForUI()

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

    public var hashValue: Int {
        return month.hashValue ^ year.hashValue
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

protocol MediaGalleryDataSource: class {
    var hasFetchedOldest: Bool { get }
    var hasFetchedMostRecent: Bool { get }

    var galleryItems: [MediaGalleryItem] { get }
    var galleryItemCount: Int { get }

    var sections: [GalleryDate: [MediaGalleryItem]] { get }
    var sectionDates: [GalleryDate] { get }

    var deletedAttachments: Set<TSAttachment> { get }
    var deletedGalleryItems: Set<MediaGalleryItem> { get }

    func ensureGalleryItemsLoaded(_ direction: GalleryDirection, item: MediaGalleryItem, amount: UInt, completion: ((IndexSet, [IndexPath]) -> Void)?)

    func galleryItem(before currentItem: MediaGalleryItem) -> MediaGalleryItem?
    func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem?

    func showAllMedia(focusedItem: MediaGalleryItem)
    func dismissMediaDetailViewController(_ mediaDetailViewController: MediaPageViewController, animated isAnimated: Bool, completion: (() -> Void)?)

    func delete(items: [MediaGalleryItem], initiatedBy: AnyObject)
}

protocol MediaGalleryDataSourceDelegate: class {
    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject)
    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, deletedSections: IndexSet, deletedItems: [IndexPath])
}

class MediaGalleryNavigationController: OWSNavigationController {

    var retainUntilDismissed: MediaGallery?

    // HACK: Though we don't have an input accessory view, the VC we are presented above (ConversationVC) does.
    // If the app is backgrounded and then foregrounded, when OWSWindowManager calls mainWindow.makeKeyAndVisible
    // the ConversationVC's inputAccessoryView will appear *above* us unless we'd previously become first responder.
    override public var canBecomeFirstResponder: Bool {
        Logger.debug("")
        return true
    }

    // MARK: View Lifecycle

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return isLightMode ? .default : .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let navigationBar = self.navigationBar as? OWSNavigationBar else {
            owsFailDebug("navigationBar had unexpected class: \(self.navigationBar)")
            return
        }

        view.backgroundColor = Colors.navigationBarBackground

        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // If the user's device is already rotated, try to respect that by rotating to landscape now
        UIViewController.attemptRotationToDeviceOrientation()
    }

    // MARK: Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
}

@objc
class MediaGallery: NSObject, MediaGalleryDataSource, MediaTileViewControllerDelegate {

    @objc
    weak public var navigationController: MediaGalleryNavigationController!

    var deletedAttachments: Set<TSAttachment> = Set()
    var deletedGalleryItems: Set<MediaGalleryItem> = Set()

    private var pageViewController: MediaPageViewController?

    private var uiDatabaseConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().uiDatabaseConnection
    }

    private let editingDatabaseConnection: YapDatabaseConnection
    private let mediaGalleryFinder: OWSMediaGalleryFinder

    private var initialDetailItem: MediaGalleryItem?
    private let thread: TSThread
    private let options: MediaGalleryOption

    // we start with a small range size for quick loading.
    private let fetchRangeSize: UInt = 10

    deinit {
        Logger.debug("")
    }

    @objc
    init(thread: TSThread, options: MediaGalleryOption = []) {
        self.thread = thread

        self.editingDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()

        self.options = options
        self.mediaGalleryFinder = OWSMediaGalleryFinder(thread: thread)
        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(uiDatabaseDidUpdate),
                                               name: .OWSUIDatabaseConnectionDidUpdate,
                                               object: OWSPrimaryStorage.shared().dbNotificationObject)
    }

    // MARK: Present/Dismiss

    private var currentItem: MediaGalleryItem {
        return self.pageViewController!.currentItem
    }

    @objc
    public func presentDetailView(fromViewController: UIViewController, mediaAttachment: TSAttachment) {
        var galleryItem: MediaGalleryItem?
        uiDatabaseConnection.read { transaction in
            galleryItem = self.buildGalleryItem(attachment: mediaAttachment, transaction: transaction)
        }

        guard let initialDetailItem = galleryItem else {
            return
        }

        presentDetailView(fromViewController: fromViewController, initialDetailItem: initialDetailItem)
    }

    public func presentDetailView(fromViewController: UIViewController, initialDetailItem: MediaGalleryItem) {
        // For a speedy load, we only fetch a few items on either side of
        // the initial message
        ensureGalleryItemsLoaded(.around, item: initialDetailItem, amount: 10)

        // We lazily load media into the gallery, but with large albums, we want to be sure
        // we load all the media required to render the album's media rail.
        ensureAlbumEntirelyLoaded(galleryItem: initialDetailItem)

        self.initialDetailItem = initialDetailItem

        let pageViewController = MediaPageViewController(initialItem: initialDetailItem, mediaGalleryDataSource: self, uiDatabaseConnection: self.uiDatabaseConnection, options: self.options)
        self.addDataSourceDelegate(pageViewController)

        self.pageViewController = pageViewController

        let navController = MediaGalleryNavigationController()
        self.navigationController = navController
        navController.retainUntilDismissed = self

        navigationController.setViewControllers([pageViewController], animated: false)

        navigationController.modalPresentationStyle = .fullScreen
        navigationController.modalTransitionStyle = .crossDissolve

        fromViewController.present(navigationController, animated: true, completion: nil)
    }

    // If we're using a navigationController other than self to present the views
    // e.g. the conversation settings view controller
    var fromNavController: OWSNavigationController?

    @objc
    func pushTileView(fromNavController: OWSNavigationController) {
        var mostRecentItem: MediaGalleryItem?
        self.uiDatabaseConnection.read { transaction in
            if let attachment = self.mediaGalleryFinder.mostRecentMediaAttachment(transaction: transaction) {
                mostRecentItem = self.buildGalleryItem(attachment: attachment, transaction: transaction)
            }
        }

        if let mostRecentItem = mostRecentItem {
            mediaTileViewController.focusedItem = mostRecentItem
            ensureGalleryItemsLoaded(.around, item: mostRecentItem, amount: 100)
        }
        self.fromNavController = fromNavController
        fromNavController.pushViewController(mediaTileViewController, animated: true)
    }

    func showAllMedia(focusedItem: MediaGalleryItem) {
        // TODO fancy animation - zoom media item into it's tile in the all media grid
        ensureGalleryItemsLoaded(.around, item: focusedItem, amount: 100)

        if let fromNavController = self.fromNavController {
            // If from conversation settings view, we've already pushed
            fromNavController.popViewController(animated: true)
        } else {
            // If from conversation view
            mediaTileViewController.focusedItem = focusedItem
            navigationController.pushViewController(mediaTileViewController, animated: true)
        }
    }

    // MARK: MediaTileViewControllerDelegate

    func mediaTileViewController(_ viewController: MediaTileViewController, didTapView tappedView: UIView, mediaGalleryItem: MediaGalleryItem) {
        if self.fromNavController != nil {
            // If we got to the gallery via conversation settings, present the detail view
            // on top of the tile view
            //
            // == ViewController Schematic ==
            //
            // [DetailView] <--,
            // [TileView] -----'
            // [ConversationSettingsView]
            // [ConversationView]
            //

            self.presentDetailView(fromViewController: mediaTileViewController, initialDetailItem: mediaGalleryItem)
        } else {
            // If we got to the gallery via the conversation view, pop the tile view
            // to return to the detail view
            //
            // == ViewController Schematic ==
            //
            // [TileView] -----,
            // [DetailView] <--'
            // [ConversationView]
            //

            guard let pageViewController = self.pageViewController else {
                owsFailDebug("pageViewController was unexpectedly nil")
                self.navigationController.dismiss(animated: true)

                return
            }

            pageViewController.setCurrentItem(mediaGalleryItem, direction: .forward, animated: false)
            pageViewController.willBePresentedAgain()

            // TODO fancy zoom animation
            self.navigationController.popViewController(animated: true)
        }
    }

    public func dismissMediaDetailViewController(_ mediaPageViewController: MediaPageViewController, animated isAnimated: Bool, completion completionParam: (() -> Void)?) {

        guard let presentingViewController = self.navigationController.presentingViewController else {
            owsFailDebug("presentingController was unexpectedly nil")
            return
        }

        let completion = {
            completionParam?()
            UIApplication.shared.isStatusBarHidden = false
            presentingViewController.setNeedsStatusBarAppearanceUpdate()
        }

        navigationController.view.isUserInteractionEnabled = false

        presentingViewController.dismiss(animated: true, completion: completion)
    }

    // MARK: - Database Notifications

    @objc
    func uiDatabaseDidUpdate(notification: Notification) {
        guard let notifications = notification.userInfo?[OWSUIDatabaseConnectionNotificationsKey] as? [Notification] else {
            owsFailDebug("notifications was unexpectedly nil")
            return
        }

        guard mediaGalleryFinder.hasMediaChanges(in: notifications, dbConnection: uiDatabaseConnection) else {
            Logger.verbose("no changes for thread: \(thread)")
            return
        }

        let rowChanges = extractRowChanges(notifications: notifications)
        assert(rowChanges.count > 0)

        process(rowChanges: rowChanges)
    }

    func extractRowChanges(notifications: [Notification]) -> [YapDatabaseViewRowChange] {
        return notifications.flatMap { notification -> [YapDatabaseViewRowChange] in
            guard let userInfo = notification.userInfo else {
                owsFailDebug("userInfo was unexpectedly nil")
                return []
            }

            guard let extensionChanges = userInfo["extensions"] as? [AnyHashable: Any] else {
                owsFailDebug("extensionChanges was unexpectedly nil")
                return []
            }

            guard let galleryData = extensionChanges[OWSMediaGalleryFinder.databaseExtensionName()] as? [AnyHashable: Any] else {
                owsFailDebug("galleryData was unexpectedly nil")
                return []
            }

            guard let galleryChanges = galleryData["changes"] as? [Any] else {
                owsFailDebug("gallerlyChanges was unexpectedly nil")
                return []
            }

            return galleryChanges.compactMap { $0 as? YapDatabaseViewRowChange }
        }
    }

    func process(rowChanges: [YapDatabaseViewRowChange]) {
        let deleteChanges = rowChanges.filter { $0.type == .delete }

        let deletedItems: [MediaGalleryItem] = deleteChanges.compactMap { (deleteChange: YapDatabaseViewRowChange) -> MediaGalleryItem? in
            guard let deletedItem = self.galleryItems.first(where: { galleryItem in
                galleryItem.attachmentStream.uniqueId == deleteChange.collectionKey.key
            }) else {
                Logger.debug("deletedItem was never loaded - no need to remove.")
                return nil
            }

            return deletedItem
        }

        self.delete(items: deletedItems, initiatedBy: self)
    }

    // MARK: - MediaGalleryDataSource

    lazy var mediaTileViewController: MediaTileViewController = {
        let vc = MediaTileViewController(mediaGalleryDataSource: self, uiDatabaseConnection: self.uiDatabaseConnection)
        vc.delegate = self

        self.addDataSourceDelegate(vc)

        return vc
    }()

    var galleryItems: [MediaGalleryItem] = []
    var sections: [GalleryDate: [MediaGalleryItem]] = [:]
    var sectionDates: [GalleryDate] = []
    var hasFetchedOldest = false
    var hasFetchedMostRecent = false

    func buildGalleryItem(attachment: TSAttachment, transaction: YapDatabaseReadTransaction) -> MediaGalleryItem? {
        guard let attachmentStream = attachment as? TSAttachmentStream else {
            return nil
        }

        guard let message = attachmentStream.fetchAlbumMessage(with: transaction) else {
            return nil
        }

        let galleryItem = MediaGalleryItem(message: message, attachmentStream: attachmentStream)
        galleryItem.album = getAlbum(item: galleryItem)

        return galleryItem
    }

    func ensureAlbumEntirelyLoaded(galleryItem: MediaGalleryItem) {
        ensureGalleryItemsLoaded(.before, item: galleryItem, amount: UInt(galleryItem.albumIndex))

        let followingCount = galleryItem.message.attachmentIds.count - 1 - galleryItem.albumIndex
        guard followingCount >= 0 else {
            return
        }
        ensureGalleryItemsLoaded(.after, item: galleryItem, amount: UInt(followingCount))
    }

    var galleryAlbums: [String: MediaGalleryAlbum] = [:]
    func getAlbum(item: MediaGalleryItem) -> MediaGalleryAlbum? {
        guard let albumMessageId = item.attachmentStream.albumMessageId else {
            return nil
        }

        guard let existingAlbum = galleryAlbums[albumMessageId] else {
            let newAlbum = MediaGalleryAlbum(items: [item])
            galleryAlbums[albumMessageId] = newAlbum
            newAlbum.mediaGalleryDataSource = self
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

    func ensureGalleryItemsLoaded(_ direction: GalleryDirection, item: MediaGalleryItem, amount: UInt, completion: ((IndexSet, [IndexPath]) -> Void)? = nil ) {

        var galleryItems: [MediaGalleryItem] = self.galleryItems
        var sections: [GalleryDate: [MediaGalleryItem]] = self.sections
        var sectionDates: [GalleryDate] = self.sectionDates

        var newGalleryItems: [MediaGalleryItem] = []
        var newDates: [GalleryDate] = []

        do {
            try Bench(title: "fetching gallery items") {
                try self.uiDatabaseConnection.read { transaction in
                    guard let index = self.mediaGalleryFinder.mediaIndex(attachment: item.attachmentStream, transaction: transaction) else {
                        throw MediaGalleryError.itemNoLongerExists
                    }
                    let initialIndex: Int = index.intValue
                    let mediaCount: Int = Int(self.mediaGalleryFinder.mediaCount(transaction: transaction))

                    let requestRange: Range<Int> = { () -> Range<Int> in
                        let range: Range<Int> = { () -> Range<Int> in
                            switch direction {
                            case .around:
                                // To keep it simple, this isn't exactly *amount* sized if `message` window overlaps the end or
                                // beginning of the view. Still, we have sufficient buffer to fetch more as the user swipes.
                                let start: Int = initialIndex - Int(amount) / 2
                                let end: Int = initialIndex + Int(amount) / 2 + 1

                                return start..<end
                            case .before:
                                let start: Int = initialIndex - Int(amount)
                                let end: Int = initialIndex

                                return start..<end
                            case  .after:
                                let start: Int = initialIndex
                                let end: Int = initialIndex  + Int(amount) + 1

                                return start..<end
                            }
                        }()

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
                    let isFetchingEdgeOfGallery = (self.fetchedIndexSet.count - unfetchedSet.count) < requestSet.count

                    guard isSubstantialRequest || isFetchingEdgeOfGallery else {
                        Logger.debug("ignoring small fetch request: \(unfetchedSet.count)")
                        return
                    }

                    Logger.debug("fetching set: \(unfetchedSet)")
                    let nsRange: NSRange = NSRange(location: unfetchedSet.min()!, length: unfetchedSet.count)
                    self.mediaGalleryFinder.enumerateMediaAttachments(range: nsRange, transaction: transaction) { (attachment: TSAttachment) in

                        guard !self.deletedAttachments.contains(attachment) else {
                            Logger.debug("skipping \(attachment) which has been deleted.")
                            return
                        }

                        guard let item: MediaGalleryItem = self.buildGalleryItem(attachment: attachment, transaction: transaction) else {
                            owsFailDebug("unexpectedly failed to buildGalleryItem")
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

    var dataSourceDelegates: [Weak<MediaGalleryDataSourceDelegate>] = []
    func addDataSourceDelegate(_ dataSourceDelegate: MediaGalleryDataSourceDelegate) {
        dataSourceDelegates.append(Weak(value: dataSourceDelegate))
    }

    func delete(items: [MediaGalleryItem], initiatedBy: AnyObject) {
        AssertIsOnMainThread()

        Logger.info("with items: \(items.map { ($0.attachmentStream, $0.message.timestamp) })")

        deletedGalleryItems.formUnion(items)
        dataSourceDelegates.forEach { $0.value?.mediaGalleryDataSource(self, willDelete: items, initiatedBy: initiatedBy) }

        for item in items {
            self.deletedAttachments.insert(item.attachmentStream)
        }

        self.editingDatabaseConnection.asyncReadWrite { transaction in
            for item in items {
                let message = item.message
                let attachment = item.attachmentStream
                message.removeAttachment(attachment, transaction: transaction)
                if message.attachmentIds.count == 0 {
                    Logger.debug("removing message after removing last media attachment")
                    message.remove(with: transaction)
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

        dataSourceDelegates.forEach { $0.value?.mediaGalleryDataSource(self, deletedSections: deletedSections, deletedItems: deletedIndexPaths) }
    }

    let kGallerySwipeLoadBatchSize: UInt = 5

    internal func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem? {
        Logger.debug("")

        self.ensureGalleryItemsLoaded(.after, item: currentItem, amount: kGallerySwipeLoadBatchSize)

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

        self.ensureGalleryItemsLoaded(.before, item: currentItem, amount: kGallerySwipeLoadBatchSize)

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
        var count: UInt = 0
        self.uiDatabaseConnection.read { (transaction: YapDatabaseReadTransaction) in
            count = self.mediaGalleryFinder.mediaCount(transaction: transaction)
        }
        return Int(count) - deletedAttachments.count
    }
}
