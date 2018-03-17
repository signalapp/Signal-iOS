//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

class MediaPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, MediaDetailViewControllerDelegate {

    private struct MediaGalleryItem: Equatable {
        let message: TSMessage
        let attachmentStream: TSAttachmentStream
        let viewController: MediaDetailViewController

        var isVideo: Bool {
            return attachmentStream.isVideo()
        }

        var image: UIImage {
            guard let image = attachmentStream.image() else {
                owsFail("\(logTag) in \(#function) unexpectedly unable to build attachment image")
                return UIImage()
            }

            return image
        }

        // MARK: Equatable

        static func == (lhs: MediaGalleryItem, rhs: MediaGalleryItem) -> Bool {
            return lhs.message.uniqueId == rhs.message.uniqueId
        }
    }

    private var cachedItems: [MediaGalleryItem] = []
    private var initialItem: MediaGalleryItem!
    private var currentItem: MediaGalleryItem! {
        return cachedItems.first { $0.viewController == viewControllers?.first }
    }

    private let includeGallery: Bool
    private let thread: TSThread

    private let mediaGalleryFinder: OWSMediaGalleryFinder
    private let uiDatabaseConnection: YapDatabaseConnection

    private var mediaMessages: [TSMessage] = []

    convenience init(thread: TSThread, mediaMessage: TSMessage) {
        self.init(thread: thread, mediaMessage: mediaMessage, includeGallery: true)
    }

    init(thread: TSThread, mediaMessage: TSMessage, includeGallery: Bool) {
        self.thread = thread
        self.uiDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
        self.mediaGalleryFinder = OWSMediaGalleryFinder()
        self.includeGallery = includeGallery

        let kSpacingBetweenItems: CGFloat = 20

        super.init(transitionStyle: .scroll,
                   navigationOrientation: .horizontal,
                   options: [UIPageViewControllerOptionInterPageSpacingKey: kSpacingBetweenItems])

        self.dataSource = self
        self.delegate = self

        uiDatabaseConnection.beginLongLivedReadTransaction()

        if includeGallery {
            uiDatabaseConnection.read { transaction in
                // TODO don't read all media messages in at once. Use Mapping?
                self.mediaGalleryFinder.enumerateMediaMessages(with: thread, transaction: transaction) { message in
                    self.mediaMessages.append(message)
                }
            }
        } else {
            self.mediaMessages = [mediaMessage]
        }

        guard let initialItem = self.buildGalleryItem(mediaMessage: mediaMessage, thread: thread) else {
            owsFail("unexpetedly unable to build initial gallery item")
            return
        }
        self.initialItem = initialItem
        cachedItems.insert(initialItem, at: 0)

        self.setViewControllers([initialItem.viewController], direction: .forward, animated: false, completion: nil)
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        Logger.debug("\(logTag) deinit")
    }

    var presentationView: UIImageView!
    var footerBar: UIToolbar!
    var videoPlayBarButton: UIBarButtonItem!
    var videoPauseBarButton: UIBarButtonItem!
    var pagerScrollView: UIScrollView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Navigation

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressDismissButton))

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

        // The presentationView is only used during present/dismiss animations.
        // It's a static image of the media content.
        let presentationView = UIImageView(image: currentItem.image)
        self.presentationView = presentationView
        self.view.addSubview(presentationView)
        presentationView.isHidden = true
        presentationView.clipsToBounds = true
        presentationView.layer.allowsEdgeAntialiasing = true
        presentationView.layer.minificationFilter = kCAFilterTrilinear
        presentationView.layer.magnificationFilter = kCAFilterTrilinear
        presentationView.contentMode = .scaleAspectFit

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
                self.currentItem.viewController.setShouldHideToolbars(self.shouldHideToolbars)
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

    var replacingView: UIView?

    // TODO Default to bottom of screen?
    // TODO rename to replacingOriginRect
    var originRect: CGRect?

    func present(fromViewController: UIViewController, replacingView: UIView) {

        self.replacingView = replacingView

        let convertedRect: CGRect = replacingView.convert(replacingView.bounds, to: UIApplication.shared.keyWindow)
        self.originRect = convertedRect

        // loadView hasn't necessarily been called yet.
        self.loadViewIfNeeded()
        self.applyInitialMediaViewConstraints()

        let navController = UINavigationController(rootViewController: self)

        // UIModalPresentationCustom retains the current view context behind our VC, allowing us to manually
        // animate in our view, over the existing context, similar to a cross disolve, but allowing us to have
        // more fine grained control
        navController.modalPresentationStyle = .custom
        navController.navigationBar.barTintColor = UIColor.ows_materialBlue
        navController.navigationBar.isTranslucent = false
        navController.navigationBar.isOpaque = true

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

        self.pagerScrollView.isHidden = true
        self.presentationView.isHidden = false
        self.presentationView.layer.cornerRadius = OWSMessageCellCornerRadius

        fromViewController.present(navController, animated: false) {

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

                            self.view.backgroundColor = UIColor.white
                },
                completion: { (_: Bool) in
                    // At this point our presentation view should be overlayed perfectly
                    // with our media view. Swapping them out should be imperceptible.
                    self.pagerScrollView.isHidden = false
                    self.presentationView.isHidden = true

                    self.view.isUserInteractionEnabled = true

                    guard let currentItem = self.currentItem else {
                        owsFail("\(self.logTag) in \(#function) currentItem unexepcetdly nil")
                        return
                    }
                    if currentItem.isVideo {
                        currentItem.viewController.playVideo()
                    }
            })
        }
    }

    private var presentationViewConstraints: [NSLayoutConstraint] = []

    private func applyInitialMediaViewConstraints() {
        if (self.presentationViewConstraints.count > 0) {
            NSLayoutConstraint.deactivate(self.presentationViewConstraints)
            self.presentationViewConstraints = []
        }

        guard let originRect = self.originRect else {
            owsFail("\(logTag) in \(#function) originRect was unexpectedly nil")
            return
        }

        guard let presentationSuperview = self.presentationView.superview else {
            owsFail("\(logTag) in \(#function) presentationView.superview was unexpectedly nil")
            return
        }

        let convertedRect: CGRect = presentationSuperview.convert(originRect, from: UIApplication.shared.keyWindow)

        self.presentationViewConstraints += self.presentationView.autoSetDimensions(to: convertedRect.size)
        self.presentationViewConstraints += [
            self.presentationView.autoPinEdge(toSuperviewEdge: .top, withInset:convertedRect.origin.y),
            self.presentationView.autoPinEdge(toSuperviewEdge: .left, withInset:convertedRect.origin.x)
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
            guard let pendingItem = self.cachedItems.first(where: { $0.viewController == viewController}) else {
                owsFail("\(logTag) in \(#function) unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Ensure upcoming page respects current toolbar status
            pendingItem.viewController.setShouldHideToolbars(self.shouldHideToolbars)
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted: Bool) {
        Logger.debug("\(logTag) in \(#function)")

        assert(previousViewControllers.count == 1)
        previousViewControllers.forEach { viewController in
            guard let previousItem = self.cachedItems.first(where: { $0.viewController == viewController}) else {
                owsFail("\(logTag) in \(#function) unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Do any cleanup for the no-longer visible view controller
            if transitionCompleted {
                previousItem.viewController.zoomOut(animated: false)
                if previousItem.isVideo {
                    previousItem.viewController.stopVideo()
                }
                updateFooterBarButtonItems(isPlayingVideo: false)
            }
        }
    }

    // MARK: UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        Logger.debug("\(logTag) in \(#function)")
        guard let currentIndex = cachedItems.index(where: { $0.viewController == viewController }) else {
            owsFail("\(self.logTag) unknown view controller. \(viewController)")
            return nil
        }
        let currentItem = cachedItems[currentIndex]

        let newIndex = currentIndex - 1
        if let cachedItem = cachedItems[safe: newIndex] {
            return cachedItem.viewController
        }

        guard let previousMediaMessage = previousMediaMessage(currentItem.message) else {
            return nil
        }

        guard let previousItem = buildGalleryItem(mediaMessage: previousMediaMessage, thread: thread) else {
            return nil
        }

        cachedItems.insert(previousItem, at: currentIndex)
        return previousItem.viewController
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("\(logTag) in \(#function)")

        guard let currentIndex = cachedItems.index(where: { $0.viewController == viewController }) else {
            owsFail("\(self.logTag) unknown view controller. \(viewController)")
            return nil
        }
        let currentItem = cachedItems[currentIndex]

        let newIndex = currentIndex + 1
        if let cachedItem = cachedItems[safe: newIndex] {
            return cachedItem.viewController
        }

        guard let nextMediaMessage = nextMediaMessage(currentItem.message) else {
            return nil
        }

        guard let nextItem = buildGalleryItem(mediaMessage: nextMediaMessage, thread: thread) else {
            return nil
        }

        cachedItems.insert(nextItem, at: newIndex)
        return nextItem.viewController
    }

    private func buildGalleryItem(mediaMessage: TSMessage, thread: TSThread) -> MediaGalleryItem? {
        var fetchedAttachment: TSAttachment? = nil
        var fetchedItem: ConversationViewItem? = nil
        self.uiDatabaseConnection.read { transaction in
            fetchedAttachment = mediaMessage.attachment(with: transaction)
            fetchedItem = ConversationViewItem(interaction: mediaMessage, isGroupThread: thread.isGroupThread(), transaction: transaction)
        }

        guard let attachmentStream = fetchedAttachment as? TSAttachmentStream else {
            owsFail("attachment stream unexpectedly nil")
            return nil
        }

        guard let viewItem = fetchedItem else {
            owsFail("viewItem stream unexpectedly nil")
            return nil
        }

        let viewController = MediaDetailViewController(attachmentStream: attachmentStream, viewItem: viewItem)
        viewController.delegate = self
        return MediaGalleryItem(message: mediaMessage,
                                attachmentStream: attachmentStream,
                                viewController: viewController)
    }

    @nonobjc
    public func presentationCount(for: UIPageViewController) -> Int {
        Logger.debug("\(logTag) in \(#function)")

        var count: UInt = 0
        self.uiDatabaseConnection.read { (transaction: YapDatabaseReadTransaction) in
            count = self.mediaGalleryFinder.mediaCount(thread: self.thread, transaction: transaction)
        }
        return Int(count)
    }

    @nonobjc
    public func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        Logger.debug("\(logTag) in \(#function)")

        guard let mediaPageViewController = pageViewController as? MediaPageViewController else {
            owsFail("\(self.logTag) unknown view controller. \(pageViewController)")
            return 0
        }

        var index: UInt = 0
        self.uiDatabaseConnection.read { (transaction: YapDatabaseReadTransaction) in
            index = self.mediaGalleryFinder.mediaIndex(message: self.currentItem.message, transaction: transaction)
        }
        return Int(index)
    }

    // MARK: MediaDetailViewControllerDelegate

    public func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        self.view.isUserInteractionEnabled = false
        UIApplication.shared.isStatusBarHidden = false

        guard let currentItem = self.currentItem else {
            owsFail("\(logTag) in \(#function) currentItem was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: false, completion: completion)
            return
        }

        // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
        currentItem.viewController.zoomOut(animated: true)

        self.pagerScrollView.isHidden = true
        self.presentationView.isHidden = false

        // Move the presentationView back to it's initial position, i.e. where
        // it sits on the screen in the conversation view.
        let changedItems = currentItem != initialItem
        if changedItems {
            self.presentationView.image = currentItem.image
            self.applyOffscreenMediaViewConstraints()
        } else {
            self.applyInitialMediaViewConstraints()
        }

        if isAnimated {
            UIView.animate(withDuration: changedItems ? 0.25 : 0.18,
                           delay: 0.0,
                           options:.curveEaseOut,
                           animations: {
                            self.presentationView.superview?.layoutIfNeeded()

                            // In case user has hidden bars, which changes background to black.
                            self.view.backgroundColor = UIColor.white

                            if changedItems {
                                self.presentationView.alpha = 0
                            } else {
                                self.presentationView.layer.cornerRadius = OWSMessageCellCornerRadius
                            }
            },
                           completion:nil)

            // This intentionally overlaps the previous animation a bit
            UIView.animate(withDuration: 0.1,
                           delay: 0.15,
                           options: .curveEaseInOut,
                           animations: {
                            guard let replacingView = self.replacingView else {
                                owsFail("\(self.logTag) in \(#function) replacingView was unexpectedly nil")
                                self.presentingViewController?.dismiss(animated: false, completion: completion)
                                return
                            }
                            replacingView.alpha = 1.0

                            // fade out content and toolbars
                            self.navigationController?.view.alpha = 0.0
            },
                           completion: { (_: Bool) in
                            self.presentingViewController?.dismiss(animated: false, completion: completion)
            })
        } else {
            guard let replacingView = self.replacingView else {
                owsFail("\(self.logTag) in \(#function) replacingView was unexpectedly nil")
                self.presentingViewController?.dismiss(animated: false, completion: completion)
                return
            }
            replacingView.alpha = 1.0
            self.presentingViewController?.dismiss(animated: false, completion: completion)
        }
    }

    public func mediaDetailViewController(_ mediaDetailViewController: MediaDetailViewController, isPlayingVideo: Bool) {
        guard mediaDetailViewController == currentItem.viewController else {
            Logger.verbose("\(logTag) in \(#function) ignoring stale delegate.")
            return
        }

        self.shouldHideToolbars = isPlayingVideo
        self.updateFooterBarButtonItems(isPlayingVideo: isPlayingVideo)
    }

    // MARK: Helpers

    private var threadId: String {
        guard let unqiueThreadId = self.thread.uniqueId else {
            owsFail("thread missing id in \(#function)")
            return ""
        }

        return unqiueThreadId
    }

    private func nextMediaMessage(_ message: TSMessage) -> TSMessage? {
        Logger.debug("\(logTag) in \(#function)")

        guard let currentIndex = mediaMessages.index(of: message) else {
            owsFail("currentIndex was unexpectedly nil in \(#function)")
            return nil
        }

        let index: Int = mediaMessages.index(after: currentIndex)
        return mediaMessages[safe: index]
    }

    private func previousMediaMessage(_ message: TSMessage) -> TSMessage? {
        Logger.debug("\(logTag) in \(#function)")

        guard let currentIndex = mediaMessages.index(of: message) else {
            owsFail("currentIndex was unexpectedly nil in \(#function)")
            return nil
        }

        let index: Int = mediaMessages.index(before: currentIndex)
        return mediaMessages[safe: index]
    }
}

