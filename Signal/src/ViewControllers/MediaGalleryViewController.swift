//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum GalleryDirection {
    case before, after, around
}

public class MediaGalleryItem: Equatable, Hashable {
    let message: TSMessage
    let attachmentStream: TSAttachmentStream
    let galleryDate: GalleryDate

    init(message: TSMessage, attachmentStream: TSAttachmentStream) {
        self.message = message
        self.attachmentStream = attachmentStream
        self.galleryDate = GalleryDate(message: message)
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

    public typealias AsyncThumbnailBlock = (UIImage) -> Void
    func thumbnailImage(async:@escaping AsyncThumbnailBlock) -> UIImage? {
        return attachmentStream.thumbnailImageSmall(success: async, failure: {})
    }

    // MARK: Equatable

    public static func == (lhs: MediaGalleryItem, rhs: MediaGalleryItem) -> Bool {
        return lhs.message.uniqueId == rhs.message.uniqueId
    }

    // MARK: Hashable

    public var hashValue: Int {
        return message.hashValue
    }
}

public struct GalleryDate: Hashable, Comparable, Equatable {
    let year: Int
    let month: Int

    init(message: TSMessage) {
        let date = message.dateForSorting()

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

    func ensureGalleryItemsLoaded(_ direction: GalleryDirection, item: MediaGalleryItem, amount: UInt, completion: ((IndexSet, [IndexPath]) -> Void)?)

    func galleryItem(before currentItem: MediaGalleryItem) -> MediaGalleryItem?
    func galleryItem(after currentItem: MediaGalleryItem) -> MediaGalleryItem?

    func showAllMedia(focusedItem: MediaGalleryItem)
    func dismissMediaDetailViewController(_ mediaDetailViewController: MediaPageViewController, animated isAnimated: Bool, completion: (() -> Void)?)

    func delete(items: [MediaGalleryItem], initiatedBy: MediaGalleryDataSourceDelegate)
}

protocol MediaGalleryDataSourceDelegate: class {
    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, willDelete items: [MediaGalleryItem], initiatedBy: MediaGalleryDataSourceDelegate)
    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, deletedSections: IndexSet, deletedItems: [IndexPath])
}

class MediaGalleryViewController: OWSNavigationController, MediaGalleryDataSource, MediaTileViewControllerDelegate {

    private var pageViewController: MediaPageViewController?

    private let uiDatabaseConnection: YapDatabaseConnection
    private let editingDatabaseConnection: YapDatabaseConnection
    private let mediaGalleryFinder: OWSMediaGalleryFinder

    private var initialDetailItem: MediaGalleryItem?
    private let thread: TSThread
    private let options: MediaGalleryOption

    // we start with a small range size for quick loading.
    private let fetchRangeSize: UInt = 10

    deinit {
        Logger.debug("deinit")
    }

    @objc
    init(thread: TSThread, uiDatabaseConnection: YapDatabaseConnection, options: MediaGalleryOption = []) {
        self.thread = thread
        assert(uiDatabaseConnection.isInLongLivedReadTransaction())
        self.uiDatabaseConnection = uiDatabaseConnection

        self.editingDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()

        self.options = options
        self.mediaGalleryFinder = OWSMediaGalleryFinder(thread: thread)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

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
        presentationView.layer.minificationFilter = kCAFilterTrilinear
        presentationView.layer.magnificationFilter = kCAFilterTrilinear
        presentationView.contentMode = .scaleAspectFit
    }

    // MARK: Present/Dismiss

    private var currentItem: MediaGalleryItem {
        return self.pageViewController!.currentItem
    }

    private var replacingView: UIView?
    private var presentationView: UIImageView!
    private var presentationViewConstraints: [NSLayoutConstraint] = []

    // TODO rename to replacingOriginRect
    private var originRect: CGRect?

    @objc
    public func presentDetailView(fromViewController: UIViewController, mediaMessage: TSMessage, replacingView: UIView) {
        var galleryItem: MediaGalleryItem?
        uiDatabaseConnection.read { transaction in
            galleryItem = self.buildGalleryItem(message: mediaMessage, transaction: transaction)!
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
        self.initialDetailItem = initialDetailItem

        let pageViewController = MediaPageViewController(initialItem: initialDetailItem, mediaGalleryDataSource: self, uiDatabaseConnection: self.uiDatabaseConnection, options: self.options)
        self.addDataSourceDelegate(pageViewController)

        self.pageViewController = pageViewController
        self.setViewControllers([pageViewController], animated: false)

        self.replacingView = replacingView

        let convertedRect: CGRect = replacingView.convert(replacingView.bounds, to: UIApplication.shared.keyWindow)
        self.originRect = convertedRect

        // loadView hasn't necessarily been called yet.
        self.loadViewIfNeeded()

        self.presentationView.image = initialDetailItem.attachmentStream.thumbnailImageLarge(success: { [weak self] (image) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.presentationView.image = image
            }, failure: {
                Logger.warn("Could not load presentation image.")
        })

        self.applyInitialMediaViewConstraints()

        // Restore presentationView.alpha in case a previous dismiss left us in a bad state.
        self.setNavigationBarHidden(false, animated: false)
        self.presentationView.alpha = 1

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
        self.view.alpha = 0.0

        guard let detailView = pageViewController.view else {
            owsFailDebug("detailView was unexpectedly nil")
            return
        }

        // At this point our media view should be overlayed perfectly
        // by our presentationView. Swapping them out should be imperceptible.
        self.presentationView.isHidden = false
        // We don't hide the pageViewController entirely - e.g. we want the toolbars to fade in.
        pageViewController.currentViewController.view.isHidden = true
        detailView.backgroundColor = .clear
        self.view.backgroundColor = .clear

        self.presentationView.layer.cornerRadius = kOWSMessageCellCornerRadius_Small

        fromViewController.present(self, animated: false) {

            // 1. Fade in the entire view.
            UIView.animate(withDuration: 0.1) {
                self.replacingView?.alpha = 0.0
                self.view.alpha = 1.0
            }

            self.presentationView.superview?.layoutIfNeeded()
            self.applyFinalMediaViewConstraints()

            // 2. Animate imageView from it's initial position, which should match where it was
            // in the presenting view to it's final position, front and center in this view. This
            // animation duration intentionally overlaps the previous
            UIView.animate(withDuration: 0.2,
                           delay: 0.08,
                           options: .curveEaseOut,
                           animations: {

                            self.presentationView.layer.cornerRadius = 0
                            self.presentationView.superview?.layoutIfNeeded()

                            // fade out content behind the pageViewController
                            // and behind the presentation view
                            self.view.backgroundColor = Theme.backgroundColor
            },
                           completion: { (_: Bool) in
                            // At this point our presentation view should be overlayed perfectly
                            // with our media view. Swapping them out should be imperceptible.
                            pageViewController.currentViewController.view.isHidden = false
                            self.presentationView.isHidden = true

                            self.view.isUserInteractionEnabled = true

                            pageViewController.wasPresented()

                            // Since we're presenting *over* the ConversationVC, we need to `becomeFirstResponder`.
                            //
                            // Otherwise, the `ConversationVC.inputAccessoryView` will appear over top of us whenever
                            // OWSWindowManager window juggling calls `[rootWindow makeKeyAndVisible]`.
                            //
                            // We don't need to do this when pushing VCs onto the SignalsNavigationController - only when
                            // presenting directly from ConversationVC.
                            _ = self.becomeFirstResponder()
            })
        }
    }

    // If we're using a navigationController other than self to present the views
    // e.g. the conversation settings view controller
    var fromNavController: OWSNavigationController?

    @objc
    func pushTileView(fromNavController: OWSNavigationController) {
        var mostRecentItem: MediaGalleryItem?
        self.uiDatabaseConnection.read { transaction in
            if let message = self.mediaGalleryFinder.mostRecentMediaMessage(transaction: transaction) {
                mostRecentItem = self.buildGalleryItem(message: message, transaction: transaction)
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
            self.pushViewController(mediaTileViewController, animated: true)
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
                self.dismiss(animated: true)

                return
            }

            pageViewController.currentItem = mediaGalleryItem
            pageViewController.willBePresentedAgain()

            // TODO fancy zoom animation
            self.popViewController(animated: true)
        }
    }

    public func dismissMediaDetailViewController(_ mediaPageViewController: MediaPageViewController, animated isAnimated: Bool, completion: (() -> Void)?) {
        self.view.isUserInteractionEnabled = false
        UIApplication.shared.isStatusBarHidden = false

        guard let detailView = mediaPageViewController.view else {
            owsFailDebug("detailView was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: false, completion: completion)
            return
        }

        mediaPageViewController.currentViewController.view.isHidden = true
        self.presentationView.isHidden = false

        // Move the presentationView back to it's initial position, i.e. where
        // it sits on the screen in the conversation view.
        let changedItems = currentItem != self.initialDetailItem
        if changedItems {
            self.presentationView.image = currentItem.attachmentStream.thumbnailImageLarge(success: { [weak self] (image) in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.presentationView.image = image
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
                            self.presentationView.superview?.layoutIfNeeded()

                            detailView.alpha = 0

                            if changedItems {
                                self.presentationView.alpha = 0
                            } else {
                                self.presentationView.layer.cornerRadius = kOWSMessageCellCornerRadius_Small
                            }
            },
                           completion: { (_: Bool) in
                            // In case user has hidden bars, which changes background to black.
                            // We don't want to change this while detailView is visible, lest
                            // we obscure out the presentationView
                            detailView.backgroundColor = Theme.backgroundColor
            })

            // This intentionally overlaps the previous animation a bit
            UIView.animate(withDuration: 0.1,
                           delay: 0.15,
                           options: .curveEaseInOut,
                           animations: {
                            guard let replacingView = self.replacingView else {
                                owsFailDebug("replacingView was unexpectedly nil")
                                self.presentingViewController?.dismiss(animated: false, completion: completion)
                                return
                            }
                            // fade out content and toolbars
                            self.view.alpha = 0.0
                            replacingView.alpha = 1.0
            },
                           completion: { (_: Bool) in
                            self.presentingViewController?.dismiss(animated: false, completion: completion)
            })
        } else {
            guard let replacingView = self.replacingView else {
                owsFailDebug("replacingView was unexpectedly nil")
                self.presentingViewController?.dismiss(animated: false, completion: completion)
                return
            }
            replacingView.alpha = 1.0
            self.presentingViewController?.dismiss(animated: false, completion: completion)
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

        guard let presentationSuperview = self.presentationView.superview else {
            owsFailDebug("presentationView.superview was unexpectedly nil")
            return
        }

        let convertedRect: CGRect = presentationSuperview.convert(originRect, from: UIApplication.shared.keyWindow)

        self.presentationViewConstraints += self.presentationView.autoSetDimensions(to: convertedRect.size)
        self.presentationViewConstraints += [
            self.presentationView.autoPinEdge(toSuperviewEdge: .top, withInset: convertedRect.origin.y),
            self.presentationView.autoPinEdge(toSuperviewEdge: .left, withInset: convertedRect.origin.x)
        ]
    }

    private func applyFinalMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        self.presentationViewConstraints = [
            self.presentationView.autoPinEdge(toSuperviewEdge: .leading),
            self.presentationView.autoPinEdge(toSuperviewEdge: .top),
            self.presentationView.autoPinEdge(toSuperviewEdge: .trailing),
            self.presentationView.autoPinEdge(toSuperviewEdge: .bottom)
        ]
    }

    private func applyOffscreenMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        self.presentationViewConstraints += [
            self.presentationView.autoPinEdge(toSuperviewEdge: .leading),
            self.presentationView.autoPinEdge(toSuperviewEdge: .trailing),
            self.presentationView.autoPinEdge(.top, to: .bottom, of: self.view)
        ]
    }

    // MARK: MediaGalleryDataSource

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

    func buildGalleryItem(message: TSMessage, transaction: YapDatabaseReadTransaction) -> MediaGalleryItem? {
        guard let attachmentStream = message.attachment(with: transaction) as? TSAttachmentStream else {
            owsFailDebug("attachment was unexpectedly empty")
            return nil
        }

        return MediaGalleryItem(message: message, attachmentStream: attachmentStream)
    }

    // Range instead of indexSet since it's contiguous?
    var fetchedIndexSet = IndexSet() {
        didSet {
            Logger.debug("\(oldValue) -> \(fetchedIndexSet)")
        }
    }

    func ensureGalleryItemsLoaded(_ direction: GalleryDirection, item: MediaGalleryItem, amount: UInt, completion: ((IndexSet, [IndexPath]) -> Void)? = nil ) {

        var galleryItems: [MediaGalleryItem] = self.galleryItems
        var sections: [GalleryDate: [MediaGalleryItem]] = self.sections
        var sectionDates: [GalleryDate] = self.sectionDates

        var newGalleryItems: [MediaGalleryItem] = []
        var newDates: [GalleryDate] = []

        Bench(title: "fetching gallery items") {
            self.uiDatabaseConnection.read { transaction in

                let initialIndex: Int = Int(self.mediaGalleryFinder.mediaIndex(message: item.message, transaction: transaction))
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
                self.mediaGalleryFinder.enumerateMediaMessages(range: nsRange, transaction: transaction) { (message: TSMessage) in

                    guard !self.deletedMessages.contains(message) else {
                        Logger.debug("skipping \(message) which has been deleted.")
                        return
                    }

                    guard let item: MediaGalleryItem = self.buildGalleryItem(message: message, transaction: transaction) else {
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

        // TODO only sort if changed
        var sortedSections: [GalleryDate: [MediaGalleryItem]] = [:]

        Bench(title: "sorting gallery items") {
            galleryItems.sort { lhs, rhs -> Bool in
                return lhs.message.timestampForSorting() < rhs.message.timestampForSorting()
            }
            sectionDates.sort()

            for (date, galleryItems) in sections {
                sortedSections[date] = galleryItems.sorted { lhs, rhs -> Bool in
                    return lhs.message.timestampForSorting() < rhs.message.timestampForSorting()
                }
            }
        }

        self.galleryItems = galleryItems
        self.sections = sortedSections
        self.sectionDates = sectionDates

        if let completionBlock = completion {
            Bench(title: "calculating changes for collectionView") {
                // FIXME can we avoid this index offset?
                let dateIndices = newDates.map { sectionDates.index(of: $0)! + 1 }
                let addedSections: IndexSet = IndexSet(dateIndices)

                let addedItems: [IndexPath] = newGalleryItems.map { galleryItem in
                    let sectionIdx = sectionDates.index(of: galleryItem.galleryDate)!
                    let section = sections[galleryItem.galleryDate]!
                    let itemIdx = section.index(of: galleryItem)!

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

    var deletedMessages: Set<TSMessage> = Set()
    var deletedGalleryItems: Set<MediaGalleryItem> = Set()

    func delete(items: [MediaGalleryItem], initiatedBy: MediaGalleryDataSourceDelegate) {
        AssertIsOnMainThread()

        Logger.info("with items: \(items.map { ($0.attachmentStream, $0.message.timestamp) })")

        deletedGalleryItems.formUnion(items)
        dataSourceDelegates.forEach { $0.value?.mediaGalleryDataSource(self, willDelete: items, initiatedBy: initiatedBy) }

        self.editingDatabaseConnection.asyncReadWrite { transaction in
            for item in items {
                let message = item.message
                message.remove(with: transaction)
                self.deletedMessages.insert(message)
            }
        }

        var deletedSections: IndexSet = IndexSet()
        var deletedIndexPaths: [IndexPath] = []
        let originalSections = self.sections
        let originalSectionDates = self.sectionDates

        for item in items {
            guard let itemIndex = galleryItems.index(of: item) else {
                owsFailDebug("removing unknown item.")
                return
            }

            self.galleryItems.remove(at: itemIndex)

            guard let sectionIndex = sectionDates.index(where: { $0 == item.galleryDate }) else {
                owsFailDebug("item with unknown date.")
                return
            }

            guard var sectionItems = self.sections[item.galleryDate] else {
                owsFailDebug("item with unknown section")
                return
            }

            guard let sectionRowIndex = sectionItems.index(of: item) else {
                owsFailDebug("item with unknown sectionRowIndex")
                return
            }

            // We need to calculate the index of the deleted item with respect to it's original position.
            guard let originalSectionIndex = originalSectionDates.index(where: { $0 == item.galleryDate }) else {
                owsFailDebug("item with unknown date.")
                return
            }

            guard let originalSectionItems = originalSections[item.galleryDate] else {
                owsFailDebug("item with unknown section")
                return
            }

            guard let originalSectionRowIndex = originalSectionItems.index(of: item) else {
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

        guard let currentIndex = galleryItems.index(of: currentItem) else {
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

        guard let currentIndex = galleryItems.index(of: currentItem) else {
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
        return Int(count) - deletedMessages.count
    }
}
