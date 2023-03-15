//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI
import UIKit

class MediaPageViewController: UIPageViewController {
    private lazy var mediaInteractiveDismiss = MediaInteractiveDismiss(targetViewController: self)

    private let isShowingSingleMessage: Bool
    let mediaGallery: MediaGallery

    convenience init(initialMediaAttachment: TSAttachment, thread: TSThread, showingSingleMessage: Bool = false) {
        self.init(
            initialMediaAttachment: initialMediaAttachment,
            mediaGallery: MediaGallery(thread: thread),
            showingSingleMessage: showingSingleMessage
        )
    }

    init(initialMediaAttachment: TSAttachment, mediaGallery: MediaGallery, showingSingleMessage: Bool = false) {
        self.mediaGallery = mediaGallery
        self.isShowingSingleMessage = showingSingleMessage

        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )

        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
        dataSource = self
        delegate = self
        transitioningDelegate = self

        Logger.info("will ensureLoadedForDetailView")
        guard let initialItem = mediaGallery.ensureLoadedForDetailView(focusedAttachment: initialMediaAttachment) else {
            owsFailDebug("unexpectedly failed to build initialDetailItem.")
            return
        }
        Logger.info("ensureLoadedForDetailView done")

        mediaGallery.addDelegate(self)

        guard let initialPage = buildGalleryPage(galleryItem: initialItem, shouldAutoPlayVideo: true) else {
            owsFailBeta("unexpectedly unable to build initial gallery item")
            return
        }
        setViewControllers([initialPage], direction: .forward, animated: false, completion: nil)
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        Logger.debug("deinit")
    }

    // MARK: - Controls

    private var needsCompactToolbars: Bool {
        traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .compact
    }

    // Top Bar
    private lazy var topPanel = buildsChromePanelView()
    private var topBarVerticalPositionConstraint: NSLayoutConstraint?
    private var topBarHeightConstraint: NSLayoutConstraint?
    private var topBarHeight: CGFloat { needsCompactToolbars ? 32 : 44 }

    // Bottom Bar
    private lazy var bottomPanel = buildsChromePanelView()
    private lazy var footerBar = UIToolbar.clear()
    private var footerBarHeight: CGFloat { topBarHeight }
    private var footerBarHeightConstraint: NSLayoutConstraint?

    private lazy var captionContainerView: CaptionContainerView = {
        let view = CaptionContainerView()
        view.delegate = self
        return view
    }()
    private lazy var galleryRailView: GalleryRailView = {
        let view = GalleryRailView()
        view.delegate = self
        view.itemSize = 40
        view.layoutMargins.bottom = 0
        view.isScrollEnabled = false
        view.preservesSuperviewLayoutMargins = true
        return view
    }()

    // MARK: UIViewController

    override var preferredStatusBarStyle: UIStatusBarStyle {
        let useDarkContentStatusBar: Bool
        if mediaInteractiveDismiss.interactionInProgress {
            useDarkContentStatusBar = true
        } else if isBeingDismissed, let transitionCoordinator {
            useDarkContentStatusBar = !transitionCoordinator.isCancelled
        } else {
            useDarkContentStatusBar = false
        }

        if useDarkContentStatusBar {
            if #available(iOS 13, *) {
                return .darkContent
            }
            return .default
        }
        return .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        return shouldHideStatusBar
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .none
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.darkThemeBackgroundColor

        mediaInteractiveDismiss.addGestureRecognizer(to: view)

        // Even though bars are opaque, we want content to be laid out behind them.
        // The bars might obscure part of the content, but they can easily be hidden by tapping
        // The alternative would be that content would shift when the navbars hide.
        extendedLayoutIncludesOpaqueBars = true

        // Get reference to paged content which lives in a scrollView created by the superclass.
        // Track scrolling position and show/hide caption as necessary.
        if let pagerScrollView = view.subviews.last(where: { $0 is UIScrollView }) as? UIScrollView {
            pagerScrollViewContentOffsetObservation = pagerScrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                self.pagerScrollView(pagerScrollView, contentOffsetDidChange: change)
            }
        } else {
            owsFail("pagerScrollView == nil")
        }

        // Top bar
        view.addSubview(topPanel)
        topPanel.autoPinWidthToSuperview()
        topPanel.autoPinEdge(toSuperviewEdge: .top)

        // Use UINavigation bar to ensure position of the < back button matches exactly of one in the presenting VC.
        let topBar = UINavigationBar()
        topBar.delegate = self
        topBar.tintColor = Theme.darkThemePrimaryColor
        if #available(iOS 13, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            topBar.standardAppearance = appearance
            topBar.compactAppearance = appearance
            topBar.scrollEdgeAppearance = appearance
            topBar.overrideUserInterfaceStyle = .dark
        } else {
            topBar.barTintColor = .clear
            topBar.isTranslucent = false
        }
        topBar.setItems([ UINavigationItem(title: ""), navigationItem ], animated: false)
        topPanel.addSubview(topBar)
        topBar.autoPinEdge(toSuperviewSafeArea: .leading)
        topBar.autoPinEdge(toSuperviewSafeArea: .trailing)
        topBar.autoPinEdge(toSuperviewEdge: .bottom)
        // See `viewSafeAreaInsetsDidChange` why this is needed.
        topBarVerticalPositionConstraint = topBar.autoPinEdge(toSuperviewEdge: .top)
        topBarHeightConstraint = topBar.autoSetDimension(.height, toSize: topBarHeight)

        navigationItem.titleView = headerView
        navigationItem.rightBarButtonItem = contextMenuBarButton

        updateContextMenuButtonIcon()

        // Bottom bar
        view.addSubview(bottomPanel)
        bottomPanel.autoPinWidthToSuperview()
        bottomPanel.autoPinEdge(toSuperviewEdge: .bottom)

        footerBar.tintColor = Theme.darkThemePrimaryColor
        footerBarHeightConstraint = footerBar.autoSetDimension(.height, toSize: footerBarHeight)

        let bottomStack = UIStackView(arrangedSubviews: [captionContainerView, galleryRailView, footerBar])
        bottomStack.axis = .vertical
        bottomStack.preservesSuperviewLayoutMargins = true
        bottomPanel.addSubview(bottomStack)
        bottomStack.autoPinWidthToSuperview()
        bottomStack.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
        bottomStack.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        updateCaption(item: currentItem)
        updateCaptionContainerVisibility()
        updateTitle()
        updateMediaRail(animated: false)
        updateContextMenuActions()
        updateFooterBarButtonItems(isPlayingVideo: true)

        // Gestures
        let verticalSwipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeView))
        verticalSwipe.direction = [.up, .down]
        view.addGestureRecognizer(verticalSwipe)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        setNeedsStatusBarAppearanceUpdate()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if let topBarHeightConstraint {
            topBarHeightConstraint.constant = topBarHeight
        }
        if let footerBarHeightConstraint {
            footerBarHeightConstraint.constant = footerBarHeight
        }
        updateContextMenuButtonIcon()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if let topBarVerticalPositionConstraint {
            // On iPhones with a Dynamic Island standard position of a navigation bar is bottom of the status bar,
            // which is ~5 dp smaller than the top safe area (https://useyourloaf.com/blog/iphone-14-screen-sizes/) .
            // Since it is not possible to constrain top edge of our manually maintained navigation bar to that position
            // the workaround is to detect exactly safe area of 59 points and decrease it.
            var topInset = view.safeAreaInsets.top
            if topInset == 59 {
                topInset -= 5 + CGHairlineWidth()
            }
            topBarVerticalPositionConstraint.constant = topInset
        }
    }

    override func didReceiveMemoryWarning() {
        Logger.info("")
        super.didReceiveMemoryWarning()
        cachedPages.removeAll()
    }

    // MARK: Paging

    private var cachedPages: [MediaGalleryItem: MediaItemViewController] = [:]

    private var currentViewController: MediaItemViewController? {
        let viewController = viewControllers?.first as? MediaItemViewController
        owsAssertBeta(viewController != nil)
        return viewController
    }

    private var currentItem: MediaGalleryItem! {
        return currentViewController?.galleryItem
    }

    private func setCurrentItem(
        _ item: MediaGalleryItem,
        direction: UIPageViewController.NavigationDirection,
        animated isAnimated: Bool
    ) {
        guard let galleryPage = self.buildGalleryPage(galleryItem: item) else {
            owsFailDebug("unexpectedly unable to build new gallery page")
            return
        }

        updateTitle(item: item)
        updateCaption(item: item)
        setViewControllers([galleryPage], direction: direction, animated: isAnimated)
        updateFooterBarButtonItems(isPlayingVideo: false)
        updateMediaRail(animated: isAnimated)
        updateContextMenuActions()
    }

    private var mostRecentAlbum: MediaGalleryAlbum?

    // MARK: KVO

    private var pagerScrollViewContentOffsetObservation: NSKeyValueObservation?
    private func pagerScrollView(_ pagerScrollView: UIScrollView, contentOffsetDidChange change: NSKeyValueObservedChange<CGPoint>) {
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

    func willBePresentedAgain() {
        updateFooterBarButtonItems(isPlayingVideo: false)
    }

    func wasPresented() {
        guard let currentViewController else { return }

        if currentViewController.galleryItem.isVideo {
            currentViewController.playVideo()
        }
    }

    private var shouldHideToolbars: Bool = false {
        didSet {
            guard oldValue != shouldHideToolbars else { return }

            setNeedsStatusBarAppearanceUpdate()

            currentViewController?.setShouldHideToolbars(shouldHideToolbars)
            bottomPanel.isHidden = shouldHideToolbars
            topPanel.isHidden = shouldHideToolbars
        }
    }

    private var shouldHideStatusBar: Bool {
        guard !UIDevice.current.isIPad else { return shouldHideToolbars }

        return shouldHideToolbars || traitCollection.verticalSizeClass == .compact
    }

    // MARK: Context Menu

    private func updateContextMenuButtonIcon() {
        guard let button = contextMenuBarButton.customView as? UIButton else {
            owsFailDebug("button is nil")
            return
        }
        if #available(iOS 13, *) {
            let iconSize: CGFloat = needsCompactToolbars ? 18 : 22
            let buttonImage = UIImage(systemName: "ellipsis.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: iconSize))
            button.setImage(buttonImage, for: .normal)
        } else {
            button.setImage(UIImage(imageLiteralResourceName: "ellipsis-circle-20"), for: .normal)
            // TODO: 24 pt icon for portrait orientation
        }
    }

    private func updateContextMenuActions() {
        guard let contextMenuButton = contextMenuBarButton.customView as? ContextMenuButton else {
            owsFailDebug("contextMenuButton == nil")
            return
        }

        var contextMenuActions: [ContextMenuAction] = []
        // TODO: Video Playback Speed
        // TODO: Edit
        contextMenuActions.append(ContextMenuAction(
            title: NSLocalizedString(
                "MEDIA_VIEWER_DELETE_MEDIA_ACTION",
                comment: "Context menu item in media viewer. Refers to deleting currently displayed photo/video."
            ),
            image: UIImage(imageLiteralResourceName: "trash-outline-24"),
            attributes: .destructive,
            handler: { [weak self] _ in
                self?.deleteCurrentMedia()
            }))
        contextMenuButton.contextMenu = ContextMenu(contextMenuActions)
    }

    // MARK: Bar Buttons

    private lazy var contextMenuBarButton: UIBarButtonItem = {
        let contextButton = ContextMenuButton()
        contextButton.showsContextMenuAsPrimaryAction = true
        contextButton.forceDarkTheme = true
        return UIBarButtonItem(customView: contextButton)
    }()

    private lazy var shareBarButton = UIBarButtonItem(
        image: UIImage(imageLiteralResourceName: "share-outline-24"),
        landscapeImagePhone: UIImage(imageLiteralResourceName: "share-outline-20"),
        style: .plain,
        target: self,
        action: #selector(didPressShare)
    )

    private lazy var forwardBarButton: UIBarButtonItem = {
        let barButton: UIBarButtonItem
        if #available(iOS 13, *) {
            let imageName: String
            if #available(iOS 14, *) {
                imageName = "arrowshape.turn.up.forward"
            } else {
                imageName = CurrentAppContext().isRTL ? "arrowshape.turn.up.left" : "arrowshape.turn.up.right"
            }
            barButton = UIBarButtonItem(
                image: UIImage(systemName: imageName),
                style: .plain,
                target: self,
                action: #selector(didPressForward)
            )
        } else {
            barButton = UIBarButtonItem(
               image: UIImage(imageLiteralResourceName: "forward-outline-24"),
               landscapeImagePhone: UIImage(imageLiteralResourceName: "forward-outline-20"),
               style: .plain,
               target: self,
               action: #selector(didPressForward)
           )
        }
        return barButton
    }()

    private func buildFlexibleSpace() -> UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    }

    private lazy var videoPlayBarButton: UIBarButtonItem = {
        let videoPlayBarButton = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(didPressPlayBarButton))
        videoPlayBarButton.tintColor = Theme.darkThemePrimaryColor
        return videoPlayBarButton
    }()

    private lazy var videoPauseBarButton: UIBarButtonItem = {
        let videoPauseBarButton = UIBarButtonItem(barButtonSystemItem: .pause, target: self, action: #selector(didPressPauseBarButton))
        videoPauseBarButton.tintColor = Theme.darkThemePrimaryColor
        return videoPauseBarButton
    }()

    private func updateFooterBarButtonItems(isPlayingVideo: Bool) {
        var toolbarItems: [UIBarButtonItem] = [
            shareBarButton,
            buildFlexibleSpace()
        ]

        if currentItem.isVideo {
            toolbarItems += [
                isPlayingVideo ? videoPauseBarButton : videoPlayBarButton,
                buildFlexibleSpace()
            ]
        }

        toolbarItems.append(forwardBarButton)

        footerBar.setItems(toolbarItems, animated: false)
    }

    // MARK: Media Rail

    private static var galleryCellConfiguration = GalleryRailCellConfiguration(
        cornerRadius: 6,
        itemBorderWidth: 0,
        itemBorderColor: nil,
        focusedItemBorderWidth: 2,
        focusedItemBorderColor: .white,
        focusedItemOverlayColor: nil
    )

    private func updateMediaRail(animated: Bool) {
        if mostRecentAlbum?.items.contains(currentItem) != true {
            mostRecentAlbum = mediaGallery.album(for: currentItem)
        }

        galleryRailView.configureCellViews(
            itemProvider: mostRecentAlbum!,
            focusedItem: currentItem,
            cellViewBuilder: { _ in
                return GalleryRailCellView(configuration: MediaPageViewController.galleryCellConfiguration)
            },
            animated: animated
        )
    }

    // MARK: Helpers

    private func buildsChromePanelView() -> UIView {
        let view = UIView()
        view.tintColor = Theme.darkThemePrimaryColor
        view.preservesSuperviewLayoutMargins = true

        let blurEffect: UIBlurEffect
        if #available(iOS 13, *) {
            blurEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        } else {
            blurEffect = UIBlurEffect(style: .dark)
        }
        let blurBackgroundView = UIVisualEffectView(effect: blurEffect)
        view.addSubview(blurBackgroundView)
        blurBackgroundView.autoPinEdgesToSuperviewEdges()
        return view
    }

    private func buildRenderItem(forGalleryItem galleryItem: MediaGalleryItem) -> CVRenderItem? {
        return databaseStorage.read { transaction in
            let interactionId = galleryItem.message.uniqueId
            guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId,
                                                           transaction: transaction) else {
                owsFailDebug("Missing interaction.")
                return nil
            }
            guard let thread = TSThread.anyFetch(uniqueId: interaction.uniqueThreadId,
                                                 transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return nil
            }
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread,
                                                                           transaction: transaction)
            return CVLoader.buildStandaloneRenderItem(interaction: interaction,
                                                      thread: thread,
                                                      threadAssociatedData: threadAssociatedData,
                                                      containerView: self.view,
                                                      transaction: transaction)
        }
    }

    private func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        guard let currentViewController else { return }

        // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
        currentViewController.zoomOut(animated: true)
        currentViewController.stopVideoIfPlaying()

        navigationController?.setNavigationBarHidden(false, animated: false)

        dismiss(animated: isAnimated, completion: completion)
    }

    // MARK: Actions

    @objc
    private func didTapBackButton(_ sender: Any) {
        Logger.debug("")
        dismissSelf(animated: true)
    }

    @objc
    private func didSwipeView(sender: Any) {
        Logger.debug("")
        dismissSelf(animated: true)
    }

    @objc
    private func didPressShare(_ sender: Any) {
        guard let currentViewController else { return }
        let attachmentStream = currentViewController.galleryItem.attachmentStream
        AttachmentSharing.showShareUI(forAttachment: attachmentStream, sender: sender)
    }

    @objc
    private func didPressForward(_ sender: Any) {
        let galleryItem: MediaGalleryItem = currentItem

        guard let renderItem = buildRenderItem(forGalleryItem: galleryItem) else {
            owsFailDebug("viewItem was unexpectedly nil")
            return
        }

        // Only forward media.
        let selectionType: CVSelectionType = .primaryContent
        let selectionItem = CVSelectionItem(interactionId: renderItem.interaction.uniqueId,
                                            interactionType: renderItem.interaction.interactionType,
                                            isForwardable: true,
                                            selectionType: selectionType)
        ForwardMessageViewController.present(forSelectionItems: [selectionItem],
                                             from: self,
                                             delegate: self)
    }

    private func deleteCurrentMedia() {
        Logger.verbose("")

        guard let mediaItem = currentItem else { return }

        let actionSheet = ActionSheetController(title: nil, message: nil)
        let deleteAction = ActionSheetAction(title: CommonStrings.deleteButton,
                                             style: .destructive) { _ in
            self.mediaGallery.delete(items: [mediaItem], initiatedBy: self)
        }
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(deleteAction)

        presentActionSheet(actionSheet)
    }

    @objc
    private func didPressPlayBarButton(_ sender: Any) {
        currentViewController?.playVideo()
    }

    @objc
    private func didPressPauseBarButton(_ sender: Any) {
        currentViewController?.pauseVideo()
    }

    // MARK: Dynamic Header

    private func senderName(message: TSMessage) -> String {
        switch message {
        case let incomingMessage as TSIncomingMessage:
            return self.contactsManager.displayName(for: incomingMessage.authorAddress)
        case is TSOutgoingMessage:
            return CommonStrings.you
        default:
            owsFailDebug("Unknown message type: \(type(of: message))")
            return ""
        }
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return formatter
    }()

    private lazy var headerNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = UIFont.ows_regularFont(withSize: 17)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    private lazy var headerDateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = UIFont.ows_regularFont(withSize: 12)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    private lazy var headerView: UIView = {
        let stackView = UIStackView(arrangedSubviews: [ headerNameLabel, headerDateLabel ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 0
        stackView.distribution = .fillProportionally

        let containerView = UIView()
        containerView.layoutMargins = UIEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
        containerView.addSubview(stackView)

        stackView.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        stackView.setContentHuggingHigh()
        stackView.autoCenterInSuperview()

        return containerView
    }()

    private func updateTitle() {
        updateTitle(item: currentItem)
    }

    private func updateCaption(item: MediaGalleryItem) {
        captionContainerView.currentText = item.captionForDisplay
    }

    private func updateTitle(item: MediaGalleryItem) {
        let name = senderName(message: item.message)
        headerNameLabel.text = name

        // use sent date
        let date = Date(timeIntervalSince1970: Double(item.message.timestamp) / 1000)
        headerDateLabel.text = dateFormatter.string(from: date)
    }
}

extension MediaPageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        Logger.debug("")

        owsAssert(pendingViewControllers.count == 1)
        guard let pendingViewController = pendingViewControllers.first as? MediaItemViewController else {
            owsFailDebug("unexpected transition to: \(pendingViewControllers)")
            return
        }

        captionContainerView.pendingText = pendingViewController.galleryItem.captionForDisplay?.nilIfEmpty

        // Ensure upcoming page respects current toolbar status
        pendingViewController.setShouldHideToolbars(shouldHideToolbars)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted: Bool
    ) {
        Logger.debug("")

        owsAssert(previousViewControllers.count == 1)
        guard let previousPage = previousViewControllers.first as? MediaItemViewController else {
            owsFailDebug("unexpected transition from: \(previousViewControllers)")
            return
        }

        // Do any cleanup for the no-longer visible view controller
        if transitionCompleted {
            // This can happen when trying to page past the last (or first) view controller
            // In that case, we don't want to change the captionView.
            if previousPage != currentViewController {
                captionContainerView.completePagerTransition()
            }

            updateTitle()
            updateMediaRail(animated: true)
            previousPage.zoomOut(animated: false)
            previousPage.stopVideoIfPlaying()
            updateContextMenuActions()
            updateFooterBarButtonItems(isPlayingVideo: false)
        } else {
            captionContainerView.pendingText = nil
        }
    }
}

extension MediaPageViewController: UIPageViewControllerDataSource {
    private func itemIsAllowed(_ item: MediaGalleryItem) -> Bool {
        // Normally, we can show any media item, but if we're limited
        // to showing a single message, don't page beyond that message
        return !isShowingSingleMessage || currentItem.message == item.message
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        Logger.debug("")

        guard let currentPage = viewController as? MediaItemViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        guard let precedingItem = mediaGallery.galleryItem(before: currentPage.galleryItem), itemIsAllowed(precedingItem) else {
            return nil
        }

        guard let precedingPage = buildGalleryPage(galleryItem: precedingItem) else {
            return nil
        }

        return precedingPage
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("")

        guard let currentPage = viewController as? MediaItemViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        guard let nextItem = mediaGallery.galleryItem(after: currentPage.galleryItem), itemIsAllowed(nextItem) else {
            // no more pages
            return nil
        }

        guard let nextPage = buildGalleryPage(galleryItem: nextItem) else {
            return nil
        }

        return nextPage
    }

    private func buildGalleryPage(galleryItem: MediaGalleryItem, shouldAutoPlayVideo: Bool = false) -> MediaItemViewController? {
        if let cachedPage = cachedPages[galleryItem] {
            Logger.debug("cache hit.")
            return cachedPage
        }

        Logger.debug("cache miss.")

        let viewController = MediaItemViewController(galleryItem: galleryItem, shouldAutoPlayVideo: shouldAutoPlayVideo)
        viewController.delegate = self

        cachedPages[galleryItem] = viewController
        return viewController
    }
}

extension MediaPageViewController: InteractivelyDismissableViewController {
    func performInteractiveDismissal(animated: Bool) {
        dismissSelf(animated: true)
    }
}

extension MediaPageViewController: MediaGalleryDelegate {
    func mediaGallery(_ mediaGallery: MediaGallery, applyUpdate update: MediaGallery.Update) {
        Logger.debug("")
    }

    func mediaGallery(_ mediaGallery: MediaGallery, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject) {
        Logger.debug("")

        guard items.contains(currentItem) else {
            Logger.debug("irrelevant item")
            return
        }

        // If we setCurrentItem with (animated: true) while this VC is in the background, then
        // the next/previous cache isn't expired, and we're able to swipe back to the just-deleted vc.
        // So to get the correct behavior, we should only animate these transitions when this
        // vc is in the foreground
        let isAnimated = initiatedBy === self

        if isShowingSingleMessage {
            // In message details, which doesn't use the slider, so don't swap pages.
        } else if let nextItem = mediaGallery.galleryItem(after: currentItem) {
            setCurrentItem(nextItem, direction: .forward, animated: isAnimated)
        } else if let previousItem = mediaGallery.galleryItem(before: currentItem) {
            setCurrentItem(previousItem, direction: .reverse, animated: isAnimated)
        } else {
            // else we deleted the last piece of media, return to the conversation view
            dismissSelf(animated: true)
        }
    }

    func mediaGalleryDidDeleteItem(_ mediaGallery: MediaGallery) {
        // Either this is an internal deletion, in which case willDelete would have been called already,
        // or it's an external deletion, in which case mediaGalleryDidReloadItems would have been called already.
    }

    func mediaGalleryDidReloadItems(_ mediaGallery: MediaGallery) {
        didReloadAllSectionsInMediaGallery(mediaGallery)
    }

    func didAddSectionInMediaGallery(_ mediaGallery: MediaGallery) {
        // Does not affect the current item.
    }

    func didReloadAllSectionsInMediaGallery(_ mediaGallery: MediaGallery) {
        let attachment = currentItem.attachmentStream
        guard let reloadedItem = mediaGallery.ensureLoadedForDetailView(focusedAttachment: attachment) else {
            // Assume the item was deleted.
            dismissSelf(animated: true)
            return
        }
        setCurrentItem(reloadedItem, direction: .forward, animated: false)
    }
}

extension MediaPageViewController: MediaItemViewControllerDelegate {
    func mediaItemViewControllerDidTapMedia(_ viewController: MediaItemViewController) {
        Logger.debug("")

        shouldHideToolbars = !shouldHideToolbars
    }

    func mediaItemViewController(_ viewController: MediaItemViewController, videoPlaybackStatusDidChange isPlaying: Bool) {
        guard viewController == currentViewController else {
            Logger.verbose("ignoring stale delegate.")
            return
        }
        shouldHideToolbars = isPlaying
        updateFooterBarButtonItems(isPlayingVideo: isPlaying)
    }
}

extension MediaGalleryItem: GalleryRailItem {
    public func buildRailItemView() -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.image = thumbnailImageSync()
        return imageView
    }
}

extension MediaGalleryAlbum: GalleryRailItemProvider {
    var railItems: [GalleryRailItem] {
        return self.items
    }
}

extension MediaPageViewController: GalleryRailViewDelegate {
    func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem) {
        guard let targetItem = imageRailItem as? MediaGalleryItem else {
            owsFailDebug("unexpected imageRailItem: \(imageRailItem)")
            return
        }

        let direction: UIPageViewController.NavigationDirection
        direction = currentItem.albumIndex < targetItem.albumIndex ? .forward : .reverse
        setCurrentItem(targetItem, direction: direction, animated: true)
    }
}

extension MediaPageViewController: CaptionContainerViewDelegate {
    func captionContainerViewDidUpdateText(_ captionContainerView: CaptionContainerView) {
        updateCaptionContainerVisibility()
    }

    fileprivate func updateCaptionContainerVisibility() {
        if let currentText = captionContainerView.currentText, !currentText.isEmpty {
            captionContainerView.isHidden = false
            return
        }

        if let pendingText = captionContainerView.pendingText, !pendingText.isEmpty {
            captionContainerView.isHidden = false
            return
        }

        captionContainerView.isHidden = true
    }
}

extension MediaPageViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard let mediaView = currentViewController?.mediaView else { return nil }

        guard nil != mediaView.superview else {
            owsFailDebug("superview was unexpectedly nil")
            return nil
        }

        return MediaPresentationContext(
            mediaView: mediaView,
            presentationFrame: mediaView.frame
        )
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        defer {
            UIGraphicsEndImageContext()
        }

        // Snapshot the entire view and then apply masking to only show top and bottom panels.
        UIGraphicsBeginImageContextWithOptions(view.bounds.size, false, 0)
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            return nil
        }

        let snapshot = UIImageView(image: image)
        snapshot.frame = view.bounds
        let maskLayer = CAShapeLayer()
        maskLayer.frame = snapshot.layer.bounds
        snapshot.layer.mask = maskLayer
        let path = UIBezierPath()
        path.append(UIBezierPath(rect: topPanel.frame))
        path.append(UIBezierPath(rect: bottomPanel.frame))
        maskLayer.path = path.cgPath

        let presentationFrame = coordinateSpace.convert(snapshot.frame, from: view.superview!)

        return (snapshot, presentationFrame)
    }
}

extension MediaPageViewController: UIViewControllerTransitioningDelegate {
    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard self == presented else {
            owsFailDebug("unexpected presented: \(presented)")
            return nil
        }

        return MediaZoomAnimationController(galleryItem: currentItem)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard self == dismissed else {
            owsFailDebug("unexpected dismissed: \(dismissed)")
            return nil
        }

        let animationController = MediaDismissAnimationController(
            galleryItem: currentItem,
            interactionController: mediaInteractiveDismiss
        )
        mediaInteractiveDismiss.interactiveDismissDelegate = animationController

        return animationController
    }

    public func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let animationController = animator as? MediaDismissAnimationController,
              animationController.interactionController.interactionInProgress
        else {
            return nil
        }
        return animationController.interactionController
    }
}

extension MediaPageViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(items: [ForwardMessageItem], recipientThreads: [TSThread]) {
        dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(
                items: items,
                recipientThreads: recipientThreads,
                fromViewController: self
            )
        }
    }

    public func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }
}

extension MediaPageViewController: UINavigationBarDelegate {
    func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
        dismissSelf(animated: true)
        return false
    }
}
