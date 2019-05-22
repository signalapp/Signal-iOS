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

    public func hash(into hasher: inout Hasher) {
        if let uniqueId = attachmentStream.uniqueId {
            hasher.combine(uniqueId)
        } else {
            hasher.combine(attachmentStream)
        }
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

    var presentationView: UIImageView!
    var retainUntilDismissed: MediaGallery?

    // HACK: Though we don't have an input accessory view, the VC we are presented above (ConversationVC) does.
    // If the app is backgrounded and then foregrounded, when OWSWindowManager calls mainWindow.makeKeyAndVisible
    // the ConversationVC's inputAccessoryView will appear *above* us unless we'd previously become first responder.
    override public var canBecomeFirstResponder: Bool {
        Logger.debug("")
        return true
    }

    override public func becomeFirstResponder() -> Bool {
        Logger.debug("")
        return super.becomeFirstResponder()
    }

    override public func resignFirstResponder() -> Bool {
        Logger.debug("")
        return super.resignFirstResponder()
    }

    // MARK: View Lifecycle

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // UIModalPresentationCustom retains the current view context behind our VC, allowing us to manually
        // animate in our view, over the existing context, similar to a cross disolve, but allowing us to have
        // more fine grained control
        self.modalPresentationStyle = .custom

        // The presentationView is only used during present/dismiss animations.
        // It's a static image of the media content.
        let presentationView = UIImageView()
        self.presentationView = presentationView
        self.view.insertSubview(presentationView, at: 0)
        presentationView.isHidden = true
        presentationView.clipsToBounds = true
        presentationView.layer.allowsEdgeAntialiasing = true
        presentationView.layer.minificationFilter = .trilinear
        presentationView.layer.magnificationFilter = .trilinear
        presentationView.contentMode = .scaleAspectFit

        guard let navigationBar = self.navigationBar as? OWSNavigationBar else {
            owsFailDebug("navigationBar had unexpected class: \(self.navigationBar)")
            return
        }

        navigationBar.overrideTheme(type: .alwaysDark)
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

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private let mediaGalleryFinder: AnyMediaGalleryFinder

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

        self.options = options
        self.mediaGalleryFinder = AnyMediaGalleryFinder(thread: thread)
        super.init()

        setupDatabaseObservation()
    }

    func setupDatabaseObservation() {
        if FeatureFlags.useGRDB {
            guard let mediaGalleryDatabaseObserver = databaseStorage.grdbStorage.mediaGalleryDatabaseObserver else {
                owsFailDebug("observer was unexpectedly nil")
                return
            }
            mediaGalleryDatabaseObserver.appendSnapshotDelegate(self)
        } else {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(uiDatabaseDidUpdate),
                                                   name: .OWSUIDatabaseConnectionDidUpdate,
                                                   object: OWSPrimaryStorage.shared().dbNotificationObject)
        }
    }

    // MARK: Present/Dismiss

    private var currentItem: MediaGalleryItem {
        return self.pageViewController!.currentItem
    }

    private var replacingView: UIView?
    private var presentationViewConstraints: [NSLayoutConstraint] = []

    // TODO rename to replacingOriginRect
    private var originRect: CGRect?

    @objc
    public func presentDetailView(fromViewController: UIViewController, mediaAttachment: TSAttachment, replacingView: UIView) {
        let galleryItem: MediaGalleryItem? = databaseStorage.uiReadReturningResult { transaction in
            return self.buildGalleryItem(attachment: mediaAttachment, transaction: transaction)
        }

        guard let initialDetailItem = galleryItem else {
            owsFailDebug("unexpectedly failed to build initialDetailItem.")
            return
        }

        presentDetailView(fromViewController: fromViewController, initialDetailItem: initialDetailItem, replacingView: replacingView)
    }

    public func presentDetailView(fromViewController: UIViewController, initialDetailItem: MediaGalleryItem, replacingView: UIView) {
        // For a speedy load, we only fetch a few items on either side of
        // the initial message
        ensureGalleryItemsLoaded(.around, item: initialDetailItem, amount: 10)

        // We lazily load media into the gallery, but with large albums, we want to be sure
        // we load all the media required to render the album's media rail.
        ensureAlbumEntirelyLoaded(galleryItem: initialDetailItem)

        self.initialDetailItem = initialDetailItem

        let pageViewController = MediaPageViewController(initialItem: initialDetailItem, mediaGalleryDataSource: self, options: self.options)
        self.addDataSourceDelegate(pageViewController)

        self.pageViewController = pageViewController

        let navController = MediaGalleryNavigationController()
        self.navigationController = navController
        navController.retainUntilDismissed = self

        navigationController.setViewControllers([pageViewController], animated: false)

        self.replacingView = replacingView

        let convertedRect: CGRect = replacingView.convert(replacingView.bounds, to: UIApplication.shared.keyWindow)
        self.originRect = convertedRect

        // loadView hasn't necessarily been called yet.
        navigationController.loadViewIfNeeded()

        navigationController.presentationView.image = initialDetailItem.attachmentStream.thumbnailImageLarge(success: { [weak self] (image) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.navigationController.presentationView.image = image
            }, failure: {
                Logger.warn("Could not load presentation image.")
        })

        self.applyInitialMediaViewConstraints()

        // Restore presentationView.alpha in case a previous dismiss left us in a bad state.
        navigationController.setNavigationBarHidden(false, animated: false)
        navigationController.presentationView.alpha = 1

        // We want to animate the tapped media from it's position in the previous VC
        // to it's resting place in the center of this view controller.
        //
        // Rather than animating the actual media view in place, we animate the presentationView, which is a static
        // image of the media content. Animating the actual media view is problematic for a couple reasons:
        // 1. The media view ultimately lives in a zoomable scrollView. Getting both original positioning and the final positioning
        //    correct, involves manipulating the zoomScale and position simultaneously, which results in non-linear movement,
        //    especially noticeable on high resolution images.
        // 2. For Video views, the AVPlayerLayer content does not scale with the presentation animation. So you instead get a full scale
        //    video, wherein only the cropping is animated.
        // Using a simple image view allows us to address both these problems relatively easily.
        navigationController.view.alpha = 0.0

        guard let detailView = pageViewController.view else {
            owsFailDebug("detailView was unexpectedly nil")
            return
        }

        // At this point our media view should be overlayed perfectly
        // by our presentationView. Swapping them out should be imperceptible.
        navigationController.presentationView.isHidden = false
        // We don't hide the pageViewController entirely - e.g. we want the toolbars to fade in.
        pageViewController.currentViewController.view.isHidden = true
        detailView.backgroundColor = .clear
        navigationController.view.backgroundColor = .clear

        navigationController.presentationView.layer.cornerRadius = kOWSMessageCellCornerRadius_Small

        fromViewController.present(navigationController, animated: false) {

            // 1. Fade in the entire view.
            UIView.animate(withDuration: 0.1) {
                self.replacingView?.alpha = 0.0
                self.navigationController.view.alpha = 1.0
            }

            self.navigationController.presentationView.superview?.layoutIfNeeded()
            self.applyFinalMediaViewConstraints()

            // 2. Animate imageView from it's initial position, which should match where it was
            // in the presenting view to it's final position, front and center in this view. This
            // animation duration intentionally overlaps the previous
            UIView.animate(withDuration: 0.2,
                           delay: 0.08,
                           options: .curveEaseOut,
                           animations: {

                            self.navigationController.presentationView.layer.cornerRadius = 0
                            self.navigationController.presentationView.superview?.layoutIfNeeded()

                            // fade out content behind the pageViewController
                            // and behind the presentation view
                            self.navigationController.view.backgroundColor = Theme.darkThemeBackgroundColor
            },
                           completion: { (_: Bool) in
                            // At this point our presentation view should be overlayed perfectly
                            // with our media view. Swapping them out should be imperceptible.
                            pageViewController.currentViewController.view.isHidden = false
                            self.navigationController.presentationView.isHidden = true

                            self.navigationController.view.isUserInteractionEnabled = true

                            pageViewController.wasPresented()

                            // Since we're presenting *over* the ConversationVC, we need to `becomeFirstResponder`.
                            //
                            // Otherwise, the `ConversationVC.inputAccessoryView` will appear over top of us whenever
                            // OWSWindowManager window juggling calls `[rootWindow makeKeyAndVisible]`.
                            //
                            // We don't need to do this when pushing VCs onto the SignalsNavigationController - only when
                            // presenting directly from ConversationVC.
                            _ = self.navigationController.becomeFirstResponder()
            })
        }
    }

    // If we're using a navigationController other than self to present the views
    // e.g. the conversation settings view controller
    var fromNavController: OWSNavigationController?

    @objc
    func pushTileView(fromNavController: OWSNavigationController) {
        let mostRecentItem: MediaGalleryItem? = databaseStorage.uiReadReturningResult { transaction in
            guard let attachment = self.mediaGalleryFinder.mostRecentMediaAttachment(transaction: transaction)  else {
                return nil
            }
            return self.buildGalleryItem(attachment: attachment, transaction: transaction)
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

            self.presentDetailView(fromViewController: mediaTileViewController, initialDetailItem: mediaGalleryItem, replacingView: tappedView)
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

        guard let detailView = mediaPageViewController.view else {
            owsFailDebug("detailView was unexpectedly nil")
            self.navigationController.presentingViewController?.dismiss(animated: false, completion: completion)
            return
        }

        mediaPageViewController.currentViewController.view.isHidden = true
        navigationController.presentationView.isHidden = false

        // Move the presentationView back to it's initial position, i.e. where
        // it sits on the screen in the conversation view.
        let changedItems = currentItem != self.initialDetailItem
        if changedItems {
            navigationController.presentationView.image = currentItem.attachmentStream.thumbnailImageLarge(success: { [weak self] (image) in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.navigationController.presentationView.image = image
                }, failure: {
                    Logger.warn("Could not load presentation image.")
            })
            self.applyOffscreenMediaViewConstraints()
        } else {
            self.applyInitialMediaViewConstraints()
        }

        if isAnimated {
            UIView.animate(withDuration: changedItems ? 0.25 : 0.18,
                           delay: 0.0,
                           options: .curveEaseOut,
                           animations: {
                            // Move back over it's original location
                            self.navigationController.presentationView.superview?.layoutIfNeeded()

                            detailView.alpha = 0

                            if changedItems {
                                self.navigationController.presentationView.alpha = 0
                            } else {
                                self.navigationController.presentationView.layer.cornerRadius = kOWSMessageCellCornerRadius_Small
                            }
            })

            // This intentionally overlaps the previous animation a bit
            UIView.animate(withDuration: 0.1,
                           delay: 0.15,
                           options: .curveEaseInOut,
                           animations: {
                            guard let replacingView = self.replacingView else {
                                owsFailDebug("replacingView was unexpectedly nil")
                                presentingViewController.dismiss(animated: false, completion: completion)
                                return
                            }
                            // fade out content and toolbars
                            self.navigationController.view.alpha = 0.0
                            replacingView.alpha = 1.0
            },
                           completion: { (_: Bool) in
                            presentingViewController.dismiss(animated: false, completion: completion)
            })
        } else {
            guard let replacingView = self.replacingView else {
                owsFailDebug("replacingView was unexpectedly nil")
                presentingViewController.dismiss(animated: false, completion: completion)
                return
            }
            replacingView.alpha = 1.0
            presentingViewController.dismiss(animated: false, completion: completion)
        }
    }

    private func applyInitialMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        guard let originRect = self.originRect else {
            owsFailDebug("originRect was unexpectedly nil")
            return
        }

        guard let presentationSuperview = navigationController.presentationView.superview else {
            owsFailDebug("presentationView.superview was unexpectedly nil")
            return
        }

        let convertedRect: CGRect = presentationSuperview.convert(originRect, from: UIApplication.shared.keyWindow)

        self.presentationViewConstraints += navigationController.presentationView.autoSetDimensions(to: convertedRect.size)
        self.presentationViewConstraints += [
            navigationController.presentationView.autoPinEdge(toSuperviewEdge: .top, withInset: convertedRect.origin.y),
            navigationController.presentationView.autoPinEdge(toSuperviewEdge: .left, withInset: convertedRect.origin.x)
        ]
    }

    private func applyFinalMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        self.presentationViewConstraints = [
            navigationController.presentationView.autoPinEdge(toSuperviewEdge: .leading),
            navigationController.presentationView.autoPinEdge(toSuperviewEdge: .top),
            navigationController.presentationView.autoPinEdge(toSuperviewEdge: .trailing),
            navigationController.presentationView.autoPinEdge(toSuperviewEdge: .bottom)
        ]
    }

    private func applyOffscreenMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        self.presentationViewConstraints += [
            navigationController.presentationView.autoPinEdge(toSuperviewEdge: .leading),
            navigationController.presentationView.autoPinEdge(toSuperviewEdge: .trailing),
            navigationController.presentationView.autoPinEdge(.top, to: .bottom, of: self.navigationController.view)
        ]
    }

    // MARK: - Yap Database Notifications

    @objc
    func uiDatabaseDidUpdate(notification: Notification) {
        guard let notifications = notification.userInfo?[OWSUIDatabaseConnectionNotificationsKey] as? [Notification] else {
            owsFailDebug("notifications was unexpectedly nil")
            return
        }

        guard mediaGalleryFinder.yapAdapter.hasMediaChanges(in: notifications, dbConnection: OWSPrimaryStorage.shared().uiDatabaseConnection) else {
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

    lazy var mediaTileViewController: MediaTileViewController = {
        let vc = MediaTileViewController(mediaGalleryDataSource: self)
        vc.delegate = self

        self.addDataSourceDelegate(vc)

        return vc
    }()

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
