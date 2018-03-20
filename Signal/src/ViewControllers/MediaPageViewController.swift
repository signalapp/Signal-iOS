//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

// Objc wrapper for the MediaGalleryItem struct
@objc
public class GalleryItemBox: NSObject {
    public let value: MediaGalleryItem

    init(_ value: MediaGalleryItem) {
        self.value = value
    }

    public var attachmentStream: TSAttachmentStream {
        return value.attachmentStream
    }
}

fileprivate class Box<A> {
    var value: A
    init(_ val: A) {
        self.value = val
    }
}

fileprivate extension MediaDetailViewController {
    fileprivate var galleryItem: MediaGalleryItem {
        return self.galleryItemBox.value
    }
}

class MediaPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, MediaDetailViewControllerDelegate {

    private weak var mediaGalleryDataSource: MediaGalleryDataSource?

    private var cachedPages: [MediaGalleryItem: MediaDetailViewController] = [:]
    private var initialPage: MediaDetailViewController!

    private var currentViewController: MediaDetailViewController {
        return viewControllers!.first as! MediaDetailViewController
    }

    public var currentItem: MediaGalleryItem! {
        get {
            return currentViewController.galleryItemBox.value
        }
        set {
            guard let galleryPage = self.buildGalleryPage(galleryItem: newValue) else {
                owsFail("unexpetedly unable to build new gallery page")
                return
            }

            self.setViewControllers([galleryPage], direction: .forward, animated: false, completion: nil)
        }
    }

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
        self.setViewControllers([initialPage], direction: .forward, animated: false, completion: nil)
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

    override func didReceiveMemoryWarning() {
        Logger.info("\(logTag) in \(#function)")
        super.didReceiveMemoryWarning()

        self.cachedPages = [:]
    }

    // MARK: View Helpers

    public func willBePresentedAgain() {
        updateFooterBarButtonItems(isPlayingVideo: false)
    }

    public func wasPresented() {
        let currentViewController = self.currentViewController

        if currentViewController.galleryItem.isVideo {
            currentViewController.playVideo()
        }
    }
    @objc
    public func didPressAllMediaButton(sender: Any) {
        Logger.debug("\(logTag) in \(#function)")

        currentViewController.stopAnyVideo()

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
            return
        }
        mediaGalleryDataSource.showAllMedia(focusedItem: currentItem)
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
                self.currentViewController.setShouldHideToolbars(self.shouldHideToolbars)
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

        if (self.currentItem.isVideo) {
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
            guard let pendingPage = viewController as? MediaDetailViewController else {
                owsFail("\(logTag) in \(#function) unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Ensure upcoming page respects current toolbar status
            pendingPage.setShouldHideToolbars(self.shouldHideToolbars)
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted: Bool) {
        Logger.debug("\(logTag) in \(#function)")

        assert(previousViewControllers.count == 1)
        previousViewControllers.forEach { viewController in
            guard let previousPage = viewController as? MediaDetailViewController else {
                owsFail("\(logTag) in \(#function) unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Do any cleanup for the no-longer visible view controller
            if transitionCompleted {
                previousPage.zoomOut(animated: false)
                previousPage.stopAnyVideo()
                updateFooterBarButtonItems(isPlayingVideo: false)
            }
        }
    }

    // MARK: UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        Logger.debug("\(logTag) in \(#function)")

        guard let previousDetailViewController = viewController as? MediaDetailViewController else {
            owsFail("\(logTag) in \(#function) unexpected viewController: \(viewController)")
            return nil
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
            return nil
        }

        let previousItem = previousDetailViewController.galleryItem
        guard let nextItem: MediaGalleryItem = mediaGalleryDataSource.galleryItem(before: previousItem) else {
            return nil
        }

        guard let nextPage: MediaDetailViewController = buildGalleryPage(galleryItem: nextItem) else {
            return nil
        }

        return nextPage
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("\(logTag) in \(#function)")

        guard let previousDetailViewController = viewController as? MediaDetailViewController else {
            owsFail("\(logTag) in \(#function) unexpected viewController: \(viewController)")
            return nil
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
            return nil
        }

        let previousItem = previousDetailViewController.galleryItem
        guard let nextItem = mediaGalleryDataSource.galleryItem(after: previousItem) else {
            // no more pages
            return nil
        }

        guard let nextPage: MediaDetailViewController = buildGalleryPage(galleryItem: nextItem) else {
            return nil
        }

        return nextPage
    }

    private func buildGalleryPage(galleryItem: MediaGalleryItem) -> MediaDetailViewController? {

        if let cachedPage = cachedPages[galleryItem] {
            Logger.debug("\(logTag) in \(#function) cache hit.")
            return cachedPage
        }

        Logger.debug("\(logTag) in \(#function) cache miss.")
        var fetchedItem: ConversationViewItem? = nil
        self.uiDatabaseConnection.read { transaction in
            let message = galleryItem.message
            let thread = message.thread(with: transaction)
            fetchedItem = ConversationViewItem(interaction: message, isGroupThread: thread.isGroupThread(), transaction: transaction)
        }

        guard let viewItem = fetchedItem else {
            owsFail("viewItem was unexpectedly nil")
            return nil
        }

        let viewController = MediaDetailViewController(galleryItemBox: GalleryItemBox(galleryItem), viewItem: viewItem)
        viewController.delegate = self

        cachedPages[galleryItem] = viewController
        return viewController
    }

    // MARK: MediaDetailViewControllerDelegate

    public func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
        // currentVC
        currentViewController.zoomOut(animated: true)

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: true)

            return
        }

        mediaGalleryDataSource.dismissSelf(animated: isAnimated, completion: completion)
    }

    public func mediaDetailViewController(_ mediaDetailViewController: MediaDetailViewController, isPlayingVideo: Bool) {
        guard mediaDetailViewController == currentViewController else {
            Logger.verbose("\(logTag) in \(#function) ignoring stale delegate.")
            return
        }

        self.shouldHideToolbars = isPlayingVideo
        self.updateFooterBarButtonItems(isPlayingVideo: isPlayingVideo)
    }
}
