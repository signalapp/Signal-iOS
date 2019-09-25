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

protocol MediaPageViewDelegate: class {
    func mediaPageViewControllerDidTapAllMedia(_ mediaPageViewController: MediaPageViewController)
    func mediaPageViewControllerRequestedDismiss(_ mediaPageViewController: MediaPageViewController, animated isAnimated: Bool, completion: (() -> Void)?)
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

    func delete(items: [MediaGalleryItem], initiatedBy: AnyObject)
}

protocol MediaGalleryDataSourceDelegate: class {
    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject)
    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, deletedSections: IndexSet, deletedItems: [IndexPath])
}

@objc
public class MediaGalleryNavigationController: OWSNavigationController {

    // HACK: Though we don't have an input accessory view, the VC we are presented above (ConversationVC) does.
    // If the app is backgrounded and then foregrounded, when OWSWindowManager calls mainWindow.makeKeyAndVisible
    // the ConversationVC's inputAccessoryView will appear *above* us unless we'd previously become first responder.
    override public var canBecomeFirstResponder: Bool {
        return true
    }

    // MARK: View Lifecycle

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.darkThemeBackgroundColor
        self.modalPresentationStyle = .overFullScreen

        guard let navigationBar = self.navigationBar as? OWSNavigationBar else {
            owsFailDebug("navigationBar had unexpected class: \(self.navigationBar)")
            return
        }

        navigationBar.overrideTheme(type: .alwaysDark)
    }

    // MARK: Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    // MARK: 

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    lazy var mediaGallery = MediaGallery(thread: self.thread)

    var thread: TSThread!
    var options: MediaGalleryOption = []
    private func configure(thread: TSThread, options: MediaGalleryOption) {
        self.delegate = self
        self.transitioningDelegate = self
        self.thread = thread
        self.options = options
    }

    lazy var tileViewController: MediaTileViewController = {
        let shouldShowDismissButton: Bool
        if case .some(.tileFirst) = presentationMode {
            shouldShowDismissButton = true
        } else {
            shouldShowDismissButton = false
        }
        let vc = MediaTileViewController(mediaGalleryDataSource: mediaGallery, shouldShowDismissButton: shouldShowDismissButton)
        vc.delegate = self

        mediaGallery.addDataSourceDelegate(vc)

        return vc
    }()

    private var presentationMode: PresentationMode?

    private enum PresentationMode {
        case detailFirst, tileFirst
    }

    @objc
    class func showingDetailView(thread: TSThread, mediaAttachment: TSAttachment, options: MediaGalleryOption) -> MediaGalleryNavigationController {
        let vc = MediaGalleryNavigationController()
        vc.presentationMode = .detailFirst
        vc.configure(thread: thread, options: options)

        let galleryItem: MediaGalleryItem? = vc.databaseStorage.uiReadReturningResult { transaction in
            return vc.mediaGallery.buildGalleryItem(attachment: mediaAttachment, transaction: transaction)
        }

        guard let initialDetailItem = galleryItem else {
            owsFailDebug("unexpectedly failed to build initialDetailItem.")
            return vc
        }

        let pageViewController = vc.buildPageViewController(focusedItem: initialDetailItem)
        vc.pushViewController(pageViewController, animated: false)

        return vc
    }

    @objc
    public class func showingTileView(thread: TSThread, options: MediaGalleryOption) -> MediaGalleryNavigationController {
        let vc = MediaGalleryNavigationController()
        vc.presentationMode = .tileFirst
        vc.configure(thread: thread, options: options)

        let mostRecentItem = vc.mediaGallery.ensureLoadedForMostRecentTileView()
        vc.tileViewController.focusedItem = mostRecentItem

        vc.pushViewController(vc.tileViewController, animated: false)

        return vc
    }

    func buildPageViewController(focusedItem: MediaGalleryItem) -> MediaPageViewController {
        mediaGallery.ensureLoadedForDetailView(focusedItem: focusedItem)

        let pageViewController = MediaPageViewController(initialItem: focusedItem,
                                                         mediaGalleryDataSource: mediaGallery,
                                                         mediaPageViewDelegate: self,
                                                         options: options)

        mediaGallery.addDataSourceDelegate(pageViewController)
        pageViewController.transitioningDelegate = self

        return pageViewController
    }
}

extension MediaGalleryNavigationController: MediaPageViewDelegate {

    func mediaPageViewControllerDidTapAllMedia(_ mediaPageViewController: MediaPageViewController) {
        let noTitleItem = UIBarButtonItem(title: " ", style: .plain, target: nil, action: nil)
        mediaPageViewController.navigationItem.backBarButtonItem = noTitleItem

        guard let focusedItem = mediaPageViewController.currentItem else {
            owsFailDebug("focusedItem was unexpectedly nil")
            return
        }

        mediaGallery.ensureGalleryItemsLoaded(.around, item: focusedItem, amount: 100)
        setViewControllers([mediaPageViewController, tileViewController], animated: true)
    }

    func mediaPageViewControllerRequestedDismiss(_ mediaPageViewController: MediaPageViewController,
                                                   animated isAnimated: Bool,
                                                   completion: (() -> Void)?) {

        guard let presentationMode = presentationMode else {
            owsFailDebug("presentationMode was unexpectedly nil")
            dismiss(animated: isAnimated, completion: completion)
            return
        }

        switch presentationMode {
        case .detailFirst:
            dismiss(animated: isAnimated, completion: completion)
        case .tileFirst:
            setViewControllers([tileViewController, mediaPageViewController], animated: false)
            popViewController(animated: isAnimated, completion: completion)
        }
    }
}

extension MediaGalleryNavigationController: MediaTileViewControllerDelegate {
    public func mediaTileViewController(_ tileViewController: MediaTileViewController, didTapView tappedView: UIView, mediaGalleryItem: MediaGalleryItem) {

        let pageViewController = buildPageViewController(focusedItem: mediaGalleryItem)
        self.setViewControllers([pageViewController, tileViewController], animated: false)

        popViewController(animated: true)
    }

    public func mediaTileViewControllerRequestedDismiss(_ tileViewController: MediaTileViewController,
                                                        animated isAnimated: Bool,
                                                        completion: (() -> Void)?) {
        assert(presentationMode == .tileFirst)
        assert(viewControllers.count == 1)
        dismiss(animated: isAnimated, completion: completion)
    }
}

extension MediaGalleryNavigationController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController,
                                    presenting: UIViewController,
                                    source: UIViewController) -> UIViewControllerAnimatedTransitioning? {

        guard self == presented else {
            owsFailDebug("unexpected presented: \(presented)")
            return nil
        }

        guard let presentationMode = presentationMode else {
            owsFailDebug("presentationMode was unexpectedly nil")
            return nil
        }

        switch presentationMode {
        case .detailFirst:
            guard let detailVC = viewControllers.first as? MediaPageViewController else {
                owsFailDebug("unexpected viewControllers: \([viewControllers])")
                return nil
            }

            guard let currentItem = detailVC.currentItem else {
                owsFailDebug("currentItem was unexpectedly nil")
                return nil
            }

            return MediaZoomAnimationController(galleryItem: currentItem)
        case .tileFirst:
            // use system default modal presentation
            return nil
        }
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard self == dismissed else {
            owsFailDebug("unexpected presented: \(dismissed)")
            return nil
        }

        guard let presentationMode = presentationMode else {
            owsFailDebug("presentationMode was unexpectedly nil")
            return nil
        }

        switch presentationMode {
        case .detailFirst:
            guard let detailVC = viewControllers.first as? MediaPageViewController else {
                owsFailDebug("unexpected viewControllers: \([viewControllers])")
                return nil
            }

            guard let currentItem = detailVC.currentItem else {
                owsFailDebug("currentItem was unexpectedly nil")
                return nil
            }

            let animationController = MediaDismissAnimationController(galleryItem: currentItem,
                                                                      interactionController: detailVC.mediaInteractiveDismiss)
            guard let mediaInteractiveDismiss = detailVC.mediaInteractiveDismiss else {
                owsFailDebug("mediaInteractiveDismiss was unexpectedly nil")
                return nil
            }
            mediaInteractiveDismiss.interactiveDismissDelegate = animationController

            return animationController
        case .tileFirst:
            // use system default modal presentation
            return nil
        }
    }

    public func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let animator = animator as? MediaDismissAnimationController,
            let interactionController = animator.interactionController,
            interactionController.interactionInProgress
            else {
                return nil
        }
        return interactionController
    }
}

extension MediaGalleryNavigationController: UINavigationControllerDelegate {
    public func navigationController(_ navigationController: UINavigationController,
                                     animationControllerFor operation: UINavigationController.Operation,
                                     from fromVC: UIViewController,
                                     to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch toVC {
        case let mediaPageViewController as MediaPageViewController:
            switch operation {
            case .none:
                return nil
            case .push, .pop:
                guard let galleryItem = mediaPageViewController.currentItem else {
                    owsFailDebug("galleryItem was unexpectedly nil")
                    return nil
                }
                return MediaZoomAnimationController(galleryItem: galleryItem)
            @unknown default:
                owsFailDebug("unexpected operation: \(operation)")
                return nil
            }
        case is MediaTileViewController:
            guard let mediaPageViewController = fromVC as? MediaPageViewController else {
                owsFailDebug("unexpected fromVC: \(fromVC)")
                return nil
            }

            switch operation {
            case .none:
                owsFailDebug("unexpected operation: \(operation)")
                return nil
            case .push, .pop:
                guard let currentItem = mediaPageViewController.currentItem else {
                    owsFailDebug("galleryItem was unexpectedly nil")
                    return nil
                }
                let animationController = MediaDismissAnimationController(galleryItem: currentItem,
                                                                          interactionController: mediaPageViewController.mediaInteractiveDismiss)
                guard let mediaInteractiveDismiss = mediaPageViewController.mediaInteractiveDismiss else {
                    owsFailDebug("mediaInteractiveDismiss was unexpectedly nil")
                    return nil
                }
                mediaInteractiveDismiss.interactiveDismissDelegate = animationController

                return animationController
            @unknown default:
                owsFailDebug("unknown operation: \(operation)")
                return nil
            }
        default:
            owsFailDebug("unexpected toVC: \(toVC)")
            return nil
        }
    }

    public func navigationController(_ navigationController: UINavigationController,
                                     interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let animationController = animationController as? MediaDismissAnimationController,
            let interactionController = animationController.interactionController,
            interactionController.interactionInProgress else {
            return nil
        }
        return interactionController
    }
}

extension MediaGalleryNavigationController: MediaPresentationContextProvider {
    func mediaPresentationContext(galleryItem: MediaGalleryItem, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        return proxy?.mediaPresentationContext(galleryItem: galleryItem, in: coordinateSpace)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        guard let proxy = proxy else {
            return nil
        }
        view.layoutIfNeeded()

        guard let navigationBar = self.navigationBar as? OWSNavigationBar else {
            owsFailDebug("unexpected navigatinoBar: \(self.navigationBar)")
            return nil
        }

        guard let navbarSnapshot = navigationBar.snapshotViewIncludingBackground(afterScreenUpdates: true) else {
            owsFailDebug("navbarSnapshot was unexpectedly nil")
            return nil
        }

        guard let (proxySnapshot, proxySnapshotFrame) = proxy.snapshotOverlayView(in: self.view) else {
            return nil
        }

        let container = UIView()
        container.frame = view.frame
        container.addSubview(navbarSnapshot)

        container.addSubview(proxySnapshot)
        proxySnapshot.frame = proxySnapshotFrame

        let viewFrame = self.view.convert(view.bounds, to: coordinateSpace)
        let presentationFrame = viewFrame
        return (container, presentationFrame)
    }

    private var proxy: MediaPresentationContextProvider? {
        guard let topViewController = topViewController else {
            owsFailDebug("topVC was unexpectedly nil")
            return nil
        }

        switch topViewController {
        case let detailView as MediaPageViewController:
            return detailView
        default:
            owsFailDebug("unexpected topViewController: \(topViewController)")
            return nil
        }
    }
}

// TODO - move MediaGallery to a separate file

class MediaGallery: MediaGalleryDataSource {

    // MARK: - Dependencies

    private var primaryStorage: OWSPrimaryStorage? {
        return SSKEnvironment.shared.primaryStorage
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
        if FeatureFlags.storageMode != .ydb {
            guard let mediaGalleryDatabaseObserver = databaseStorage.grdbStorage.mediaGalleryDatabaseObserver else {
                owsFailDebug("observer was unexpectedly nil")
                return
            }
            mediaGalleryDatabaseObserver.appendSnapshotDelegate(self)
        } else {
            guard let primaryStorage = primaryStorage else {
                owsFail("Missing primaryStorage.")
            }

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(uiDatabaseDidUpdate),
                                                   name: .OWSUIDatabaseConnectionDidUpdate,
                                                   object: primaryStorage.dbNotificationObject)
        }
    }

    // MARK: - Yap Database Notifications

    @objc
    func uiDatabaseDidUpdate(notification: Notification) {
        guard let primaryStorage = primaryStorage else {
            owsFail("Missing primaryStorage.")
        }

        guard let notifications = notification.userInfo?[OWSUIDatabaseConnectionNotificationsKey] as? [Notification] else {
            owsFailDebug("notifications was unexpectedly nil")
            return
        }

        guard mediaGalleryFinder.yapAdapter.hasMediaChanges(in: notifications, dbConnection: primaryStorage.uiDatabaseConnection) else {
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

            guard let galleryData = extensionChanges[YAPDBMediaGalleryFinder.databaseExtensionName()] as? [AnyHashable: Any] else {
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
        let deletedIds = rowChanges.filter { $0.type == .delete }.map { $0.collectionKey.key }

        process(deletedAttachmentIds: deletedIds)
    }

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

        delete(items: deletedItems, initiatedBy: self)
    }

    // MARK: - MediaGalleryDataSource

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

    // MARK: - Loading

    func ensureGalleryItemsLoaded(_ direction: GalleryDirection, item: MediaGalleryItem, amount: UInt, completion: ((IndexSet, [IndexPath]) -> Void)? = nil ) {

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

                    let requestRange: Range<Int> = { () -> Range<Int> in
                        let range: Range<Int> = { () -> Range<Int> in
                            switch direction {
                            case .around:
                                // To keep it simple, this isn't exactly *amount* sized if `message` window overlaps the end or
                                // beginning of the view. Still, we have sufficient buffer to fetch more as the user swipes.
                                let start: Int = initialIndex - Int(amount) / 2
                                let end: Int = initialIndex + Int(amount) / 2

                                return start..<end
                            case .before:
                                let start: Int = initialIndex - Int(amount)
                                let end: Int = initialIndex

                                return start..<end
                            case  .after:
                                let start: Int = initialIndex
                                let end: Int = initialIndex  + Int(amount)

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

    public func ensureLoadedForDetailView(focusedItem: MediaGalleryItem) {
        // For a speedy load, we only fetch a few items on either side of
        // the initial message
        ensureGalleryItemsLoaded(.around, item: focusedItem, amount: 10)

        // We lazily load media into the gallery, but with large albums, we want to be sure
        // we load all the media required to render the album's media rail.
        ensureAlbumEntirelyLoaded(galleryItem: focusedItem)
    }

    func ensureLoadedForMostRecentTileView() -> MediaGalleryItem? {
        guard let mostRecentItem: MediaGalleryItem = (databaseStorage.uiReadReturningResult { transaction in
            guard let attachment = self.mediaGalleryFinder.mostRecentMediaAttachment(transaction: transaction)  else {
                return nil
            }
            return self.buildGalleryItem(attachment: attachment, transaction: transaction)
        }) else {
            return nil
        }

        ensureGalleryItemsLoaded(.around, item: mostRecentItem, amount: 100)
        return mostRecentItem
    }

    // MARK: -

    private var _dataSourceDelegates: [Weak<MediaGalleryDataSourceDelegate>] = []

    var dataSourceDelegates: [MediaGalleryDataSourceDelegate] {
        return _dataSourceDelegates.compactMap { $0.value }
    }

    func addDataSourceDelegate(_ dataSourceDelegate: MediaGalleryDataSourceDelegate) {
        _dataSourceDelegates = _dataSourceDelegates.filter({ $0.value != nil}) + [Weak(value: dataSourceDelegate)]
    }

    func delete(items: [MediaGalleryItem], initiatedBy: AnyObject) {
        AssertIsOnMainThread()

        Logger.info("with items: \(items.map { ($0.attachmentStream, $0.message.timestamp) })")

        deletedGalleryItems.formUnion(items)
        dataSourceDelegates.forEach { $0.mediaGalleryDataSource(self, willDelete: items, initiatedBy: initiatedBy) }

        for item in items {
            self.deletedAttachments.insert(item.attachmentStream)
        }

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

        dataSourceDelegates.forEach { $0.mediaGalleryDataSource(self, deletedSections: deletedSections, deletedItems: deletedIndexPaths) }
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
        let count: UInt = databaseStorage.uiReadReturningResult { transaction in
            return self.mediaGalleryFinder.mediaCount(transaction: transaction)
        }
        return Int(count) - deletedAttachments.count
    }
}

extension MediaGallery: MediaGalleryDatabaseSnapshotDelegate {
    func mediaGalleryDatabaseSnapshotWillUpdate() {
        // no-op
    }

    func mediaGalleryDatabaseSnapshotDidUpdate(deletedAttachmentIds: Set<String>) {
        process(deletedAttachmentIds: Array(deletedAttachmentIds))
    }

    func mediaGalleryDatabaseSnapshotDidUpdateExternally() {
        // no-op
    }

    func mediaGalleryDatabaseSnapshotDidReset() {
        // no-op
    }
}
