// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import PromiseKit
import SessionUIKit
import SessionMessagingKit
import SignalUtilitiesKit

class MediaPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, MediaDetailViewControllerDelegate, InteractivelyDismissableViewController {
    class DynamicallySizedView: UIView {
        override var intrinsicContentSize: CGSize { CGSize.zero }
    }
    
    fileprivate var mediaInteractiveDismiss: MediaInteractiveDismiss?
    
    public let viewModel: MediaGalleryViewModel
    private var dataChangeObservable: DatabaseCancellable?
    private var initialPage: MediaDetailViewController
    private var cachedPages: [Int64: [MediaGalleryViewModel.Item: MediaDetailViewController]] = [:]
    
    public var currentViewController: MediaDetailViewController {
        return viewControllers!.first as! MediaDetailViewController
    }

    public var currentItem: MediaGalleryViewModel.Item {
        return currentViewController.galleryItem
    }

    public func setCurrentItem(_ item: MediaGalleryViewModel.Item, direction: UIPageViewController.NavigationDirection, animated isAnimated: Bool) {
        guard let galleryPage = self.buildGalleryPage(galleryItem: item) else {
            owsFailDebug("unexpectedly unable to build new gallery page")
            return
        }
        
        // Cache and retrieve the new album items
        viewModel.loadAndCacheAlbumData(
            for: item.interactionId,
            in: self.viewModel.threadId
        )
        
        // Swap out the database observer
        dataChangeObservable?.cancel()
        viewModel.replaceAlbumObservation(toObservationFor: item.interactionId)
        startObservingChanges()

        updateTitle(item: item)
        updateCaption(item: item)
        setViewControllers([galleryPage], direction: direction, animated: isAnimated)
        updateFooterBarButtonItems(isPlayingVideo: false)
        updateMediaRail(item: item)
    }

    private let showAllMediaButton: Bool
    private let sliderEnabled: Bool

    init(
        viewModel: MediaGalleryViewModel,
        initialItem: MediaGalleryViewModel.Item,
        options: [MediaGalleryOption]
    ) {
        self.viewModel = viewModel
        self.showAllMediaButton = options.contains(.showAllMediaButton)
        self.sliderEnabled = options.contains(.sliderEnabled)
        self.initialPage = MediaDetailViewController(galleryItem: initialItem)

        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [ .interPageSpacing: 20 ]
        )
        
        self.cachedPages[initialItem.interactionId] = [initialItem: self.initialPage]
        self.initialPage.delegate = self
        self.dataSource = self
        self.delegate = self
        self.modalPresentationStyle = .overFullScreen
        self.transitioningDelegate = self
        self.setViewControllers([initialPage], direction: .forward, animated: false, completion: nil)
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder: NSCoder) {
        notImplemented()
    }

    deinit {
        Logger.debug("deinit")
    }

    // MARK: - Subview
    
    private var hasAppeared: Bool = false
    override var canBecomeFirstResponder: Bool { hasAppeared }

    override var inputAccessoryView: UIView? {
        return bottomContainer
    }

    // MARK: - Bottom Bar
    
    var bottomContainer: UIView!
    
    var footerBar: UIToolbar = {
        let result: UIToolbar = UIToolbar()
        result.clipsToBounds = true // hide 1px top-border
        result.themeTintColor = .textPrimary
        result.themeBarTintColor = .backgroundPrimary
        result.themeBackgroundColor = .backgroundPrimary
        result.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: UIBarMetrics.default)
        result.setShadowImage(UIImage(), forToolbarPosition: .any)
        result.isTranslucent = false

        return result
    }()
    
    let captionContainerView: CaptionContainerView = CaptionContainerView()
    var galleryRailView: GalleryRailView = GalleryRailView()

    var pagerScrollView: UIScrollView!

    // MARK: UIViewController overrides

    override func viewDidLoad() {
        super.viewDidLoad()

        // Navigation

        let backButton = UIViewController.createOWSBackButton(target: self, selector: #selector(didPressDismissButton))
        self.navigationItem.leftBarButtonItem = backButton
        self.navigationItem.titleView = portraitHeaderView

        if showAllMediaButton {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: MediaStrings.allMedia, style: .plain, target: self, action: #selector(didPressAllMediaButton))
        }

        // Even though bars are opaque, we want content to be layed out behind them.
        // The bars might obscure part of the content, but they can easily be hidden by tapping
        // The alternative would be that content would shift when the navbars hide.
        self.extendedLayoutIncludesOpaqueBars = true
        self.automaticallyAdjustsScrollViewInsets = false
        
        // Disable the interactivePopGestureRecognizer as we want to be able to swipe between
        // different pages
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        self.mediaInteractiveDismiss = MediaInteractiveDismiss(targetViewController: self)
        self.mediaInteractiveDismiss?.addGestureRecognizer(to: view)

        // Get reference to paged content which lives in a scrollView created by the superclass
        // We show/hide this content during presentation
        for view in self.view.subviews {
            if let pagerScrollView = view as? UIScrollView {
                pagerScrollView.contentInsetAdjustmentBehavior = .never
                self.pagerScrollView = pagerScrollView
            }
        }

        // Hack to avoid "page" bouncing when not in gallery view.
        // e.g. when getting to media details via message details screen, there's only
        // one "Page" so the bounce doesn't make sense.
        pagerScrollView.isScrollEnabled = sliderEnabled
        pagerScrollViewContentOffsetObservation = pagerScrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
            guard let strongSelf = self else { return }
            strongSelf.pagerScrollView(strongSelf.pagerScrollView, contentOffsetDidChange: change)
        }

        // Views
        pagerScrollView.themeBackgroundColor = .newConversation_background

        view.themeBackgroundColor = .newConversation_background

        captionContainerView.delegate = self
        updateCaptionContainerVisibility()

        galleryRailView.isHidden = true
        galleryRailView.delegate = self
        galleryRailView.autoSetDimension(.height, toSize: 72)
        footerBar.autoSetDimension(.height, toSize: 44)

        let bottomContainer: DynamicallySizedView = DynamicallySizedView()
        bottomContainer.clipsToBounds = true
        bottomContainer.autoresizingMask = .flexibleHeight
        bottomContainer.themeBackgroundColor = .backgroundPrimary
        self.bottomContainer = bottomContainer

        let bottomStack = UIStackView(arrangedSubviews: [captionContainerView, galleryRailView, footerBar])
        bottomStack.axis = .vertical
        bottomStack.isLayoutMarginsRelativeArrangement = true
        bottomContainer.addSubview(bottomStack)
        bottomStack.autoPinEdgesToSuperviewEdges()
        
        let galleryRailBlockingView: UIView = UIView()
        galleryRailBlockingView.themeBackgroundColor = .backgroundPrimary
        bottomStack.addSubview(galleryRailBlockingView)
        galleryRailBlockingView.pin(.top, to: .bottom, of: footerBar)
        galleryRailBlockingView.pin(.left, to: .left, of: bottomStack)
        galleryRailBlockingView.pin(.right, to: .right, of: bottomStack)
        galleryRailBlockingView.pin(.bottom, to: .bottom, of: bottomStack)
        
        updateTitle(item: currentItem)
        updateCaption(item: currentItem)
        updateMediaRail(item: currentItem)
        updateFooterBarButtonItems(isPlayingVideo: false)

        // Gestures

        let verticalSwipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeView))
        verticalSwipe.direction = [.up, .down]
        view.addGestureRecognizer(verticalSwipe)
        
        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startObservingChanges()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        hasAppeared = true
        becomeFirstResponder()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Stop observing database changes
        dataChangeObservable?.cancel()
        
        resignFirstResponder()
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        startObservingChanges()
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        // Stop observing database changes
        dataChangeObservable?.cancel()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let isLandscape = size.width > size.height
        self.navigationItem.titleView = isLandscape ? nil : self.portraitHeaderView
    }

    override func didReceiveMemoryWarning() {
        Logger.info("")
        super.didReceiveMemoryWarning()

        self.cachedPages = [:]
    }

    // MARK: KVO

    var pagerScrollViewContentOffsetObservation: NSKeyValueObservation?
    func pagerScrollView(_ pagerScrollView: UIScrollView, contentOffsetDidChange change: NSKeyValueObservedChange<CGPoint>) {
        guard let newValue = change.newValue else {
            owsFailDebug("newValue was unexpectedly nil")
            return
        }

        let width = pagerScrollView.frame.size.width
        guard width > 0 else {
            return
        }
        let ratioComplete = abs((newValue.x - width) / width)
        captionContainerView.updatePagerTransition(ratioComplete: ratioComplete)
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

    private var shouldHideToolbars: Bool = false {
        didSet {
            guard oldValue != shouldHideToolbars else { return }
            
            self.navigationController?.setNavigationBarHidden(shouldHideToolbars, animated: false)

            UIView.animate(withDuration: 0.1) {
                self.currentViewController.setShouldHideToolbars(self.shouldHideToolbars)
                self.bottomContainer.isHidden = self.shouldHideToolbars
            }
        }
    }

    // MARK: Bar Buttons

    lazy var shareBarButton: UIBarButtonItem = {
        let shareBarButton = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(didPressShare)
        )
        shareBarButton.themeTintColor = .textPrimary
        
        return shareBarButton
    }()

    lazy var deleteBarButton: UIBarButtonItem = {
        let deleteBarButton = UIBarButtonItem(
            barButtonSystemItem: .trash,
            target: self,
            action: #selector(didPressDelete)
        )
        deleteBarButton.themeTintColor = .textPrimary
        
        return deleteBarButton
    }()

    func buildFlexibleSpace() -> UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    }

    lazy var videoPlayBarButton: UIBarButtonItem = {
        let videoPlayBarButton = UIBarButtonItem(
            barButtonSystemItem: .play,
            target: self,
            action: #selector(didPressPlayBarButton)
        )
        videoPlayBarButton.themeTintColor = .textPrimary
        
        return videoPlayBarButton
    }()

    lazy var videoPauseBarButton: UIBarButtonItem = {
        let videoPauseBarButton = UIBarButtonItem(
            barButtonSystemItem: .pause,
            target: self,
            action: #selector(didPressPauseBarButton)
        )
        videoPauseBarButton.themeTintColor = .textPrimary
        
        return videoPauseBarButton
    }()

    private func updateFooterBarButtonItems(isPlayingVideo: Bool) {
        self.footerBar.setItems(
            [
                shareBarButton,
                buildFlexibleSpace(),
                (self.currentItem.isVideo && isPlayingVideo ? self.videoPauseBarButton : nil),
                (self.currentItem.isVideo && !isPlayingVideo ? self.videoPlayBarButton : nil),
                (self.currentItem.isVideo ? buildFlexibleSpace() : nil),
                deleteBarButton
            ].compactMap { $0 },
            animated: false
        )
    }

    func updateMediaRail(item: MediaGalleryViewModel.Item) {
        galleryRailView.configureCellViews(
            album: (self.viewModel.albumData[item.interactionId] ?? []),
            focusedItem: currentItem,
            cellViewBuilder: { _ in return GalleryRailCellView() }
        )
    }
    
    // MARK: - Updating
    
    private func startObservingChanges() {
        // Start observing for data changes
        dataChangeObservable = Storage.shared.start(
            viewModel.observableAlbumData,
            onError: { _ in },
            onChange: { [weak self] albumData in
                // The defaul scheduler emits changes on the main thread
                self?.handleUpdates(albumData)
            }
        )
    }
    
    private func handleUpdates(_ updatedViewData: [MediaGalleryViewModel.Item]) {
        // Determine if we swapped albums (if so we don't need to do anything else)
        guard updatedViewData.contains(where: { $0.interactionId == currentItem.interactionId }) else {
            if let updatedInteractionId: Int64 = updatedViewData.first?.interactionId {
                self.viewModel.updateAlbumData(updatedViewData, for: updatedInteractionId)
            }
            return
        }
        
        // Clear the cached pages that no longer match
        let interactionId: Int64 = currentItem.interactionId
        let updatedCachedPages: [MediaGalleryViewModel.Item: MediaDetailViewController] = cachedPages[interactionId]
            .defaulting(to: [:])
            .filter { key, _ -> Bool in updatedViewData.contains(key) }
        
        // If there are no more items in the album then dismiss the screen
        guard
            !updatedViewData.isEmpty,
            let oldIndex: Int = self.viewModel.albumData[interactionId]?.firstIndex(of: currentItem)
        else {
            self.dismissSelf(animated: true)
            return
        }
        
        // Update the caches
        self.viewModel.updateAlbumData(updatedViewData, for: interactionId)
        self.cachedPages[interactionId] = updatedCachedPages
        
        // If the current item is still available then do nothing else
        guard updatedCachedPages[currentItem] == nil else { return }
        
        // If the current item was modified within the current update then reload it (just in case)
        if let updatedCurrentItem: MediaGalleryViewModel.Item = updatedViewData.first(where: { item in item.attachment.id == currentItem.attachment.id }) {
            setCurrentItem(updatedCurrentItem, direction: .forward, animated: false)
            return
        }
        
        // Determine the next index (if it's less than 0 then pop the screen)
        let nextIndex: Int = min(oldIndex, (updatedViewData.count - 1))
        
        guard nextIndex >= 0 else {
            self.dismissSelf(animated: true)
            return
        }
        
        self.setCurrentItem(
            updatedViewData[nextIndex],
            direction: (nextIndex < oldIndex ?
                .reverse :
                .forward
            ),
            animated: true
        )
    }

    // MARK: - Actions

    @objc public func didPressAllMediaButton(sender: Any) {
        currentViewController.stopAnyVideo()
        
        // If the screen wasn't presented or it was presented from a location which isn't the
        // MediaTileViewController then just pop/dismiss the screen
        guard
            let presentingNavController: UINavigationController = (self.presentingViewController as? UINavigationController),
            !(presentingNavController.viewControllers.last is AllMediaViewController)
        else {
            guard self.navigationController?.viewControllers.count == 1 else {
                self.navigationController?.popViewController(animated: true)
                return
            }
            
            self.dismiss(animated: true)
            return
        }
        
        // Otherwise if we came via the conversation screen we need to push a new
        // instance of MediaTileViewController
        let allMediaViewController: AllMediaViewController = MediaGalleryViewModel.createAllMediaViewController(
            threadId: self.viewModel.threadId,
            threadVariant: self.viewModel.threadVariant,
            focusedAttachmentId: currentItem.attachment.id,
            performInitialQuerySync: true
        )
        
        let navController: MediaGalleryNavigationController = MediaGalleryNavigationController()
        navController.viewControllers = [allMediaViewController]
        navController.modalPresentationStyle = .overFullScreen
        navController.transitioningDelegate = allMediaViewController
        
        self.navigationController?.present(navController, animated: true)
    }

    @objc public func didSwipeView(sender: Any) {
        self.dismissSelf(animated: true)
    }

    @objc public func didPressDismissButton(_ sender: Any) {
        dismissSelf(animated: true)
    }

    @objc
    public func didPressShare(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }
        guard let originalFilePath: String = currentViewController.galleryItem.attachment.originalFilePath else {
            return
        }
        
        let shareVC = UIActivityViewController(activityItems: [ URL(fileURLWithPath: originalFilePath) ], applicationActivities: nil)
        
        if UIDevice.current.isIPad {
            shareVC.excludedActivityTypes = []
            shareVC.popoverPresentationController?.permittedArrowDirections = []
            shareVC.popoverPresentationController?.sourceView = self.view
            shareVC.popoverPresentationController?.sourceRect = self.view.bounds
        }
        
        shareVC.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
            if let activityError = activityError {
                SNLog("Failed to share with activityError: \(activityError)")
            }
            else if completed {
                SNLog("Did share with activityType: \(activityType.debugDescription)")
            }
            
            guard
                let activityType = activityType,
                activityType == .saveToCameraRoll,
                currentViewController.galleryItem.interactionVariant == .standardIncoming,
                self.viewModel.threadVariant == .contact
            else { return }
            
            Storage.shared.write { db in
                guard let thread: SessionThread = try SessionThread.fetchOne(db, id: self.viewModel.threadId) else {
                    return
                }
                
                try MessageSender.send(
                    db,
                    message: DataExtractionNotification(
                        kind: .mediaSaved(
                            timestamp: UInt64(currentViewController.galleryItem.interactionTimestampMs)
                        )
                    ),
                    interactionId: nil, // Show no interaction for the current user
                    in: thread
                )
            }
        }
        self.present(shareVC, animated: true, completion: nil)
    }

    @objc public func didPressDelete(_ sender: Any) {
        let itemToDelete: MediaGalleryViewModel.Item = self.currentItem
        let actionSheet: UIAlertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let deleteAction = UIAlertAction(
            title: "delete_message_for_me".localized(),
            style: .destructive
        ) { _ in
            Storage.shared.writeAsync { db in
                _ = try Attachment
                    .filter(id: itemToDelete.attachment.id)
                    .deleteAll(db)
                
                // Add the garbage collection job to delete orphaned attachment files
                JobRunner.add(
                    db,
                    job: Job(
                        variant: .garbageCollection,
                        behaviour: .runOnce,
                        details: GarbageCollectionJob.Details(
                            typesToCollect: [.orphanedAttachmentFiles]
                        )
                    )
                )
                
                // Delete any interactions which had all of their attachments removed
                _ = try Interaction
                    .filter(id: itemToDelete.interactionId)
                    .having(Interaction.interactionAttachments.isEmpty)
                    .deleteAll(db)
            }
        }
        actionSheet.addAction(UIAlertAction(title: "TXT_CANCEL_TITLE".localized(), style: .cancel))
        actionSheet.addAction(deleteAction)

        Modal.setupForIPadIfNeeded(actionSheet, targetView: self.view)
        self.present(actionSheet, animated: true)
    }

    // MARK: - Video interaction

    @objc public func didPressPlayBarButton() {
        guard let currentViewController = self.viewControllers?.first as? MediaDetailViewController else {
            SNLog("currentViewController was unexpectedly nil")
            return
        }
        
        currentViewController.didPressPlayBarButton()
    }

    @objc public func didPressPauseBarButton() {
        guard let currentViewController = self.viewControllers?.first as? MediaDetailViewController else {
            SNLog("currentViewController was unexpectedly nil")
            return
        }
        
        currentViewController.didPressPauseBarButton()
    }

    // MARK: UIPageViewControllerDelegate

    var pendingViewController: MediaDetailViewController?
    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        Logger.debug("")

        assert(pendingViewControllers.count == 1)
        pendingViewControllers.forEach { viewController in
            guard let pendingViewController = viewController as? MediaDetailViewController else {
                owsFailDebug("unexpected mediaDetailViewController: \(viewController)")
                return
            }
            self.pendingViewController = pendingViewController

            if let pendingCaptionText = pendingViewController.galleryItem.captionForDisplay, pendingCaptionText.count > 0 {
                self.captionContainerView.pendingText = pendingCaptionText
            } else {
                self.captionContainerView.pendingText = nil
            }

            // Ensure upcoming page respects current toolbar status
            pendingViewController.setShouldHideToolbars(self.shouldHideToolbars)
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted: Bool) {
        Logger.debug("")

        assert(previousViewControllers.count == 1)
        previousViewControllers.forEach { viewController in
            guard let previousPage = viewController as? MediaDetailViewController else {
                owsFailDebug("unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Do any cleanup for the no-longer visible view controller
            if transitionCompleted {
                pendingViewController = nil

                // This can happen when trying to page past the last (or first) view controller
                // In that case, we don't want to change the captionView.
                if (previousPage != currentViewController) {
                    captionContainerView.completePagerTransition()
                }

                updateTitle(item: currentItem)
                updateMediaRail(item: currentItem)
                previousPage.zoomOut(animated: false)
                previousPage.stopAnyVideo()
                updateFooterBarButtonItems(isPlayingVideo: false)
            } else {
                captionContainerView.pendingText = nil
            }
        }
    }

    // MARK: UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let mediaViewController: MediaDetailViewController = viewController as? MediaDetailViewController else {
            return nil
        }
        
        // First check if there is another item in the current album
        let interactionId: Int64 = mediaViewController.galleryItem.interactionId
        
        if
            let currentAlbum: [MediaGalleryViewModel.Item] = self.viewModel.albumData[interactionId],
            let index: Int = currentAlbum.firstIndex(of: mediaViewController.galleryItem),
            index > 0,
            let previousPage: MediaDetailViewController = buildGalleryPage(galleryItem: currentAlbum[index - 1])
        {
            return previousPage
        }
        
        // Then check if there is an interaction before the current album interaction
        guard let interactionIdAfter: Int64 = self.viewModel.interactionIdAfter[interactionId] else {
            return nil
        }
        
        // Cache and retrieve the new album items
        let newAlbumItems: [MediaGalleryViewModel.Item] = viewModel.loadAndCacheAlbumData(
            for: interactionIdAfter,
            in: self.viewModel.threadId
        )
        
        guard
            !newAlbumItems.isEmpty,
            let previousPage: MediaDetailViewController = buildGalleryPage(
                galleryItem: newAlbumItems[newAlbumItems.count - 1]
            )
        else {
            // Invalid state, restart the observer
            startObservingChanges()
            return nil
        }
        
        // Swap out the database observer
        dataChangeObservable?.cancel()
        viewModel.replaceAlbumObservation(toObservationFor: interactionIdAfter)
        startObservingChanges()
        
        return previousPage
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let mediaViewController: MediaDetailViewController = viewController as? MediaDetailViewController else {
            return nil
        }
        
        // First check if there is another item in the current album
        let interactionId: Int64 = mediaViewController.galleryItem.interactionId
        
        if
            let currentAlbum: [MediaGalleryViewModel.Item] = self.viewModel.albumData[interactionId],
            let index: Int = currentAlbum.firstIndex(of: mediaViewController.galleryItem),
            index < (currentAlbum.count - 1),
            let nextPage: MediaDetailViewController = buildGalleryPage(galleryItem: currentAlbum[index + 1])
        {
            return nextPage
        }
        
        // Then check if there is an interaction before the current album interaction
        guard let interactionIdBefore: Int64 = self.viewModel.interactionIdBefore[interactionId] else {
            return nil
        }

        // Cache and retrieve the new album items
        let newAlbumItems: [MediaGalleryViewModel.Item] = viewModel.loadAndCacheAlbumData(
            for: interactionIdBefore,
            in: self.viewModel.threadId
        )
        
        guard
            !newAlbumItems.isEmpty,
            let nextPage: MediaDetailViewController = buildGalleryPage(galleryItem: newAlbumItems[0])
        else {
            // Invalid state, restart the observer
            startObservingChanges()
            return nil
        }
        
        // Swap out the database observer
        dataChangeObservable?.cancel()
        viewModel.replaceAlbumObservation(toObservationFor: interactionIdBefore)
        startObservingChanges()
        
        return nextPage
    }

    private func buildGalleryPage(galleryItem: MediaGalleryViewModel.Item) -> MediaDetailViewController? {
        if let cachedPage: MediaDetailViewController = cachedPages[galleryItem.interactionId]?[galleryItem] {
            return cachedPage
        }
        
        cachedPages[galleryItem.interactionId] = (cachedPages[galleryItem.interactionId] ?? [:])
            .setting(galleryItem, MediaDetailViewController(galleryItem: galleryItem, delegate: self))
        
        return cachedPages[galleryItem.interactionId]?[galleryItem]
    }

    public func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        // If we have presented a MediaTileViewController from this screen then it will continue
        // to observe media changes and if all the items in the album this screen is showing are
        // deleted it will attempt to auto-dismiss
        guard self.presentedViewController == nil else { return }
        
        // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
        // currentVC
        currentViewController.zoomOut(animated: true)
        currentViewController.stopAnyVideo()

        self.navigationController?.view.isUserInteractionEnabled = false
        self.navigationController?.dismiss(animated: true, completion: { [weak self] in
            if !IsLandscapeOrientationEnabled() {
                UIDevice.current.ows_setOrientation(.portrait)
            }
            
            UIApplication.shared.isStatusBarHidden = false
            self?.navigationController?.presentingViewController?.setNeedsStatusBarAppearanceUpdate()
            completion?()
        })
    }

    // MARK: MediaDetailViewControllerDelegate

    public func mediaDetailViewControllerDidTapMedia(_ mediaDetailViewController: MediaDetailViewController) {
        Logger.debug("")

        self.shouldHideToolbars = !self.shouldHideToolbars
    }

    public func mediaDetailViewController(_ mediaDetailViewController: MediaDetailViewController, isPlayingVideo: Bool) {
        guard mediaDetailViewController == currentViewController else {
            Logger.verbose("ignoring stale delegate.")
            return
        }

        self.shouldHideToolbars = isPlayingVideo
        self.updateFooterBarButtonItems(isPlayingVideo: isPlayingVideo)
    }

    // MARK: - Dynamic Header

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return formatter
    }()

    lazy private var portraitHeaderNameLabel: UILabel = {
        let label: UILabel = UILabel()
        label.font = .systemFont(ofSize: Values.mediumFontSize)
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    lazy private var portraitHeaderDateLabel: UILabel = {
        let label: UILabel = UILabel()
        label.font = .systemFont(ofSize: Values.verySmallFontSize)
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    private lazy var portraitHeaderView: UIView = {
        let stackView: UIStackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 0
        stackView.distribution = .fillProportionally
        stackView.addArrangedSubview(portraitHeaderNameLabel)
        stackView.addArrangedSubview(portraitHeaderDateLabel)

        let containerView = UIView()
        containerView.layoutMargins = UIEdgeInsets(top: 2, left: 8, bottom: 4, right: 8)

        containerView.addSubview(stackView)

        stackView.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        stackView.setContentHuggingHigh()
        stackView.autoCenterInSuperview()

        return containerView
    }()

    private func updateCaption(item: MediaGalleryViewModel.Item) {
        captionContainerView.currentText = item.captionForDisplay
    }

    private func updateTitle(item: MediaGalleryViewModel.Item) {
        let targetItem: MediaGalleryViewModel.Item = item
        let threadVariant: SessionThread.Variant = self.viewModel.threadVariant
        
        let name: String = {
            switch targetItem.interactionVariant {
                case .standardIncoming:
                    return Storage.shared
                        .read { db in
                            Profile.displayName(
                                db,
                                id: targetItem.interactionAuthorId,
                                threadVariant: threadVariant
                            )
                        }
                        .defaulting(to: Profile.truncated(id: targetItem.interactionAuthorId, truncating: .middle))
                    
                case .standardOutgoing:
                    return "MEDIA_GALLERY_SENDER_NAME_YOU".localized() //"Short sender label for media sent by you"
                        
                default:
                    owsFailDebug("Unsupported message variant: \(targetItem.interactionVariant)")
                    return ""
            }
        }()
        
        portraitHeaderNameLabel.text = name

        // use sent date
        let date = Date(timeIntervalSince1970: (Double(targetItem.interactionTimestampMs) / 1000))
        let formattedDate = dateFormatter.string(from: date)
        portraitHeaderDateLabel.text = formattedDate

        let landscapeHeaderFormat = NSLocalizedString("MEDIA_GALLERY_LANDSCAPE_TITLE_FORMAT", comment: "embeds {{sender name}} and {{sent datetime}}, e.g. 'Sarah on 10/30/18, 3:29'")
        let landscapeHeaderText = String(format: landscapeHeaderFormat, name, formattedDate)
        self.title = landscapeHeaderText
        self.navigationItem.title = landscapeHeaderText
    }
    
    // MARK: - InteractivelyDismissableViewController
    
    func performInteractiveDismissal(animated: Bool) {
        dismissSelf(animated: true)
    }
}

extension MediaGalleryViewModel.Item: GalleryRailItem {
    public func buildRailItemView() -> UIView {
        let imageView: UIImageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        
        getRailImage()
            .map { [weak imageView] image in
                guard let imageView = imageView else { return }
                imageView.image = image
            }
            .retainUntilComplete()

        return imageView
    }

    public func getRailImage() -> Guarantee<UIImage> {
        return Guarantee<UIImage> { fulfill in
            self.thumbnailImage(async: { image in fulfill(image) })
        }
    }
    
    public func isEqual(to other: GalleryRailItem?) -> Bool {
        guard let otherItem: MediaGalleryViewModel.Item = other as? MediaGalleryViewModel.Item else { return false }
        
        return (self == otherItem)
    }
}

extension MediaPageViewController: GalleryRailViewDelegate {
    func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem) {
        guard let targetItem = imageRailItem as? MediaGalleryViewModel.Item else {
            owsFailDebug("unexpected imageRailItem: \(imageRailItem)")
            return
        }

        self.setCurrentItem(
            targetItem,
            direction: (currentItem.attachmentAlbumIndex < targetItem.attachmentAlbumIndex ?
                .forward :
                .reverse
            ),
            animated: true
        )
    }
}

extension MediaPageViewController: CaptionContainerViewDelegate {

    func captionContainerViewDidUpdateText(_ captionContainerView: CaptionContainerView) {
        updateCaptionContainerVisibility()
    }

    // MARK: Helpers

    func updateCaptionContainerVisibility() {
        if let currentText = captionContainerView.currentText, currentText.count > 0 {
            captionContainerView.isHidden = false
            return
        }

        if let pendingText = captionContainerView.pendingText, pendingText.count > 0 {
            captionContainerView.isHidden = false
            return
        }

        captionContainerView.isHidden = true
    }
}

// MARK: - UIViewControllerTransitioningDelegate

extension MediaPageViewController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard self == presented || self.navigationController == presented else { return nil }

        return MediaZoomAnimationController(galleryItem: currentItem)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard self == dismissed || self.navigationController == dismissed else { return nil }
        guard !self.viewModel.albumData.isEmpty else { return nil }

        let animationController = MediaDismissAnimationController(galleryItem: currentItem, interactionController: mediaInteractiveDismiss)
        mediaInteractiveDismiss?.interactiveDismissDelegate = animationController

        return animationController
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

// MARK: - MediaPresentationContextProvider

extension MediaPageViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(mediaItem: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        let mediaView = currentViewController.mediaView

        guard let mediaSuperview: UIView = mediaView.superview else { return nil }
        
        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)
        
        return MediaPresentationContext(
            mediaView: mediaView,
            presentationFrame: presentationFrame,
            cornerRadius: 0,
            cornerMask: CACornerMask()
        )
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return self.navigationController?.navigationBar.generateSnapshot(in: coordinateSpace)
    }
}
