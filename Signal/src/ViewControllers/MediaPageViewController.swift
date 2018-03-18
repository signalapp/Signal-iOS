//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

// TODO Can we make this private to MediaPageViewController?
public struct MediaGalleryPage: Equatable {

    public let viewController: MediaDetailViewController
    public let galleryItem: MediaGalleryItem

    public var message: TSMessage {
        return galleryItem.message
    }

    public var attachmentStream: TSAttachmentStream {
        return galleryItem.attachmentStream
    }

    public var isVideo: Bool {
        return galleryItem.isVideo
    }

    public var image: UIImage {
        return galleryItem.image
    }

    // MARK: Equatable

    public static func == (lhs: MediaGalleryPage, rhs: MediaGalleryPage) -> Bool {
        return lhs.galleryItem == rhs.galleryItem
    }
}

class MediaPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, MediaDetailViewControllerDelegate {

    let mediaGalleryDataSource: MediaGalleryDataSource

    private var cachedPages: [MediaGalleryPage] = []
    private var initialPage: MediaGalleryPage!

    // FIXME can this be private?
    public var currentPage: MediaGalleryPage! {
        return cachedPages.first { $0.viewController == viewControllers?.first }
    }

    // FIXME can this be private?
    public var currentItem: MediaGalleryItem! {
        get {
            return currentPage.galleryItem
        }
        set {
            // FIXME cache separate from ordering so we don't have to clear cache
            guard let galleryPage = self.buildGalleryPage(galleryItem: newValue) else {
                owsFail("unexpetedly unable to build initial gallery item")
                return
            }

            self.cachedPages = [galleryPage]
            self.setViewControllers([galleryPage.viewController], direction: .forward, animated: false, completion: nil)
        }
    }

    // TODO remove?
    private let uiDatabaseConnection: YapDatabaseConnection

    private let includeGallery: Bool

    convenience init(initialItem: MediaGalleryItem, mediaGalleryDataSource: MediaGalleryDataSource, uiDatabaseConnection: YapDatabaseConnection) {
        self.init(initialItem: initialItem, mediaGalleryDataSource: mediaGalleryDataSource, uiDatabaseConnection: uiDatabaseConnection, includeGallery: true)
    }

    init(initialItem: MediaGalleryItem, mediaGalleryDataSource: MediaGalleryDataSource, uiDatabaseConnection: YapDatabaseConnection, includeGallery: Bool) {
        assert(uiDatabaseConnection.isInLongLivedReadTransaction())
        self.uiDatabaseConnection = uiDatabaseConnection
        self.includeGallery = includeGallery
        self.mediaGalleryDataSource = mediaGalleryDataSource

        let kSpacingBetweenItems: CGFloat = 20

        super.init(transitionStyle: .scroll,
                   navigationOrientation: .horizontal,
                   options: [UIPageViewControllerOptionInterPageSpacingKey: kSpacingBetweenItems])

        self.dataSource = self
        self.delegate = self

        guard let initialPage = self.buildGalleryPage(galleryItem: initialItem) else {
            owsFail("unexpetedly unable to build initial gallery item")
            return
        }
        self.initialPage = initialPage
        cachedPages = [initialPage]
        self.setViewControllers([initialPage.viewController], direction: .forward, animated: false, completion: nil)
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        Logger.debug("\(logTag) deinit")
    }

    var footerBar: UIToolbar!
    var videoPlayBarButton: UIBarButtonItem!
    var videoPauseBarButton: UIBarButtonItem!
    var pagerScrollView: UIScrollView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Navigation

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressDismissButton))

        if includeGallery {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: MediaStrings.allMedia, style: .plain, target: self, action: #selector(didPressAllMediaButton))
        }

        // Even though bars are opaque, we want content to be layed out behind them.
        // The bars might obscure part of the content, but they can easily be hidden by tapping
        // The alternative would be that content would shift when the navbars hide.
        self.extendedLayoutIncludesOpaqueBars = true
        self.automaticallyAdjustsScrollViewInsets = false

        // Get reference to paged content which lives in a scrollView created by the superclass
        // We show/hide this content during presentation
        for view in self.view.subviews {
            if let pagerScrollView = view as? UIScrollView {
                self.pagerScrollView = pagerScrollView
            }
        }

        // Hack to avoid "page" bouncing when not in gallery view.
        // e.g. when getting to media details via message details screen, there's only
        // one "Page" so the bounce doesn't make sense.
        if !self.includeGallery {
            pagerScrollView.isScrollEnabled = false
        }

        // FIXME dynamic title with sender/date
        self.title = "Attachment"

        // Views

        let kFooterHeight: CGFloat = 44

        view.backgroundColor = UIColor.white

        let footerBar = UIToolbar()
        self.footerBar = footerBar
        footerBar.barTintColor = UIColor.ows_signalBrandBlue

        self.videoPlayBarButton = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(didPressPlayBarButton))
        self.videoPauseBarButton = UIBarButtonItem(barButtonSystemItem: .pause, target: self, action: #selector(didPressPauseBarButton))

        self.updateFooterBarButtonItems(isPlayingVideo: true)
        self.view.addSubview(footerBar)
        footerBar.autoPinWidthToSuperview()
        footerBar.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        footerBar.autoSetDimension(.height, toSize:kFooterHeight)

        // Gestures

        let doubleTap = UITapGestureRecognizer(target: nil, action: nil)
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(didTapView))
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)

        let verticalSwipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeView))
        verticalSwipe.direction = [.up, .down]
        view.addGestureRecognizer(verticalSwipe)
    }

    // MARK: View Helpers

    @objc
    public func didPressAllMediaButton(sender: Any) {
        Logger.debug("\(logTag) in \(#function)")

        self.mediaGalleryDataSource.showAllMedia()
    }

    @objc
    public func didSwipeView(sender: Any) {
        Logger.debug("\(logTag) in \(#function)")

        self.dismissSelf(animated: true)
    }

    @objc
    public func didTapView(sender: Any) {
        Logger.debug("\(logTag) in \(#function)")

        self.shouldHideToolbars = !self.shouldHideToolbars
    }

    private var shouldHideToolbars: Bool = false {
        didSet {
            if (oldValue == shouldHideToolbars) {
                return
            }

            // Hiding the status bar affects the positioning of the navbar. We don't want to show that in an animation, it's
            // better to just have everythign "flit" in/out.
            UIApplication.shared.setStatusBarHidden(shouldHideToolbars, with:.none)
            self.navigationController?.setNavigationBarHidden(shouldHideToolbars, animated: false)

            // We don't animate the background color change because the old color shows through momentarily
            // behind where the status bar "used to be".
            self.view.backgroundColor = shouldHideToolbars ? UIColor.black : UIColor.white

            UIView.animate(withDuration: 0.1) {
                self.currentPage.viewController.setShouldHideToolbars(self.shouldHideToolbars)
                self.footerBar.alpha = self.shouldHideToolbars ? 0 : 1
            }
        }
    }

    private func updateFooterBarButtonItems(isPlayingVideo: Bool) {
        // TODO do we still need this? seems like a vestige
        // from when media detail view was used for attachment approval
        if (self.footerBar == nil) {
            owsFail("\(logTag) No footer bar visible.")
            return
        }

        var toolbarItems: [UIBarButtonItem] = [
            UIBarButtonItem(barButtonSystemItem: .action, target:self, action: #selector(didPressShare)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target:nil, action:nil)
        ]

        if (self.currentPage.isVideo) {
            toolbarItems += [
                isPlayingVideo ? self.videoPauseBarButton : self.videoPlayBarButton,
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target:nil, action:nil)
            ]
        }

        toolbarItems.append(UIBarButtonItem(barButtonSystemItem: .trash,
                                            target:self,
                                            action:#selector(didPressDelete)))

        self.footerBar.setItems(toolbarItems, animated: false)
    }

    // MARK: Actions

    @objc
    public func didPressDismissButton(_ sender: Any) {
        dismissSelf(animated: true)
    }

    @objc
    public func didPressShare(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFail("\(logTag) in \(#function) currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressShare(sender)
    }

    @objc
    public func didPressDelete(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFail("\(logTag) in \(#function) currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressDelete(sender)
    }

    @objc
    public func didPressPlayBarButton(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFail("\(logTag) in \(#function) currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressPlayBarButton(sender)
    }

    @objc
    public func didPressPauseBarButton(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFail("\(logTag) in \(#function) currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressPauseBarButton(sender)
    }

    // MARK: UIPageViewControllerDelegate

    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        Logger.debug("\(logTag) in \(#function)")

        assert(pendingViewControllers.count == 1)
        pendingViewControllers.forEach { viewController in
            guard let pendingPage = self.cachedPages.first(where: { $0.viewController == viewController}) else {
                owsFail("\(logTag) in \(#function) unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Ensure upcoming page respects current toolbar status
            pendingPage.viewController.setShouldHideToolbars(self.shouldHideToolbars)
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted: Bool) {
        Logger.debug("\(logTag) in \(#function)")

        assert(previousViewControllers.count == 1)
        previousViewControllers.forEach { viewController in
            guard let previousPage = self.cachedPages.first(where: { $0.viewController == viewController}) else {
                owsFail("\(logTag) in \(#function) unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Do any cleanup for the no-longer visible view controller
            if transitionCompleted {
                previousPage.viewController.zoomOut(animated: false)
                if previousPage.isVideo {
                    previousPage.viewController.stopVideo()
                }
                updateFooterBarButtonItems(isPlayingVideo: false)
            }
        }
    }

    // MARK: UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        Logger.debug("\(logTag) in \(#function)")

        guard let currentIndex = cachedPages.index(where: { $0.viewController == viewController }) else {
            owsFail("\(self.logTag) unknown view controller. \(viewController)")
            return nil
        }
        let currentPage = cachedPages[currentIndex]

        let newIndex = currentIndex - 1
        if let cachedPage = cachedPages[safe: newIndex] {
            return cachedPage.viewController
        }

        guard let previousItem: MediaGalleryItem = mediaGalleryDataSource.galleryItem(before: currentPage.galleryItem) else {
            return nil
        }

        guard let previousPage: MediaGalleryPage = buildGalleryPage(galleryItem: previousItem) else {
            return nil
        }

        cachedPages.insert(previousPage, at: currentIndex)
        return previousPage.viewController
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("\(logTag) in \(#function)")

        guard let currentIndex = cachedPages.index(where: { $0.viewController == viewController }) else {
            owsFail("\(self.logTag) unknown view controller. \(viewController)")
            return nil
        }
        let currentPage = cachedPages[currentIndex]

        let newIndex = currentIndex + 1
        if let cachedPage = cachedPages[safe: newIndex] {
            return cachedPage.viewController
        }

        guard let nextItem: MediaGalleryItem = mediaGalleryDataSource.galleryItem(after: currentPage.galleryItem) else {
            return nil
        }

        guard let nextPage: MediaGalleryPage = buildGalleryPage(galleryItem: nextItem) else {
            return nil
        }

        cachedPages.insert(nextPage, at: newIndex)
        return nextPage.viewController
    }

    private func buildGalleryPage(galleryItem: MediaGalleryItem) -> MediaGalleryPage? {
        var fetchedItem: ConversationViewItem? = nil
        self.uiDatabaseConnection.read { transaction in
            let message = galleryItem.message
            let thread = message.thread(with: transaction)
            fetchedItem = ConversationViewItem(interaction: message, isGroupThread: thread.isGroupThread(), transaction: transaction)
        }

        guard let viewItem = fetchedItem else {
            owsFail("viewItem stream unexpectedly nil")
            return nil
        }

        let viewController = MediaDetailViewController(attachmentStream: galleryItem.attachmentStream, viewItem: viewItem)
        viewController.delegate = self

        return MediaGalleryPage(viewController: viewController, galleryItem: galleryItem)
    }

    // MARK: MediaDetailViewControllerDelegate

    public func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
        currentPage.viewController.zoomOut(animated: true)
        self.mediaGalleryDataSource.dismissSelf(animated: isAnimated, completion: completion)
    }

    public func mediaDetailViewController(_ mediaDetailViewController: MediaDetailViewController, isPlayingVideo: Bool) {
        guard mediaDetailViewController == currentPage.viewController else {
            Logger.verbose("\(logTag) in \(#function) ignoring stale delegate.")
            return
        }

        self.shouldHideToolbars = isPlayingVideo
        self.updateFooterBarButtonItems(isPlayingVideo: isPlayingVideo)
    }
}
