//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI
import UIKit

class MediaPageViewController: UIPageViewController {
    private lazy var mediaInteractiveDismiss = MediaInteractiveDismiss(targetViewController: self)

    private let isShowingSingleMessage: Bool
    let mediaGallery: MediaGallery
    let spoilerReveal: SpoilerRevealState

    private var initialGalleryItem: MediaGalleryItem?

    convenience init(
        initialMediaAttachment: TSAttachment,
        thread: TSThread,
        spoilerReveal: SpoilerRevealState,
        showingSingleMessage: Bool = false
    ) {
        self.init(
            initialMediaAttachment: initialMediaAttachment,
            mediaGallery: MediaGallery(thread: thread, spoilerReveal: spoilerReveal),
            spoilerReveal: spoilerReveal,
            showingSingleMessage: showingSingleMessage
        )
    }

    init(
        initialMediaAttachment: TSAttachment,
        mediaGallery: MediaGallery,
        spoilerReveal: SpoilerRevealState,
        showingSingleMessage: Bool = false
    ) {
        self.mediaGallery = mediaGallery
        self.spoilerReveal = spoilerReveal
        self.isShowingSingleMessage = showingSingleMessage

        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )

        extendedLayoutIncludesOpaqueBars = true
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

        initialGalleryItem = initialItem
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Controls

    private var needsCompactToolbars: Bool {
        traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .compact
    }

    // Top Bar
    private lazy var topPanel = buildChromePanelView()
    private var topBarVerticalPositionConstraint: NSLayoutConstraint?
    private var topBarHeightConstraint: NSLayoutConstraint?
    private var topBarHeight: CGFloat { needsCompactToolbars ? 32 : 44 }

    // Bottom Bar
    private lazy var bottomMediaPanel = MediaControlPanelView(
        mediaGallery: mediaGallery,
        delegate: self,
        spoilerReveal: spoilerReveal,
        isLandscapeLayout: traitCollection.verticalSizeClass == .compact
    )

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
            return .darkContent
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

        navigationItem.titleView = headerView

        // Top panel
        // Use UINavigation bar to ensure position of the < back button matches exactly of one in the presenting VC.
        let navigationBar = UINavigationBar()
        navigationBar.delegate = self
        navigationBar.tintColor = Theme.darkThemePrimaryColor
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationBar.standardAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.overrideUserInterfaceStyle = .dark
        navigationBar.setItems([ UINavigationItem(title: ""), navigationItem ], animated: false)
        topPanel.addSubview(navigationBar)
        navigationBar.autoPinEdge(toSuperviewSafeArea: .leading)
        navigationBar.autoPinEdge(toSuperviewSafeArea: .trailing)
        navigationBar.autoPinEdge(toSuperviewEdge: .bottom)
        // See `viewSafeAreaInsetsDidChange` why this is needed.
        topBarVerticalPositionConstraint = navigationBar.autoPinEdge(toSuperviewEdge: .top)
        topBarHeightConstraint = navigationBar.autoSetDimension(.height, toSize: topBarHeight)
        view.addSubview(topPanel)
        topPanel.autoPinWidthToSuperview()
        topPanel.autoPinEdge(toSuperviewEdge: .top)
        updateContextMenuButtonIcon()

        // Bottom panel
        view.addSubview(bottomMediaPanel)
        bottomMediaPanel.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)

        updateControlsForCurrentOrientation()

        // Load initial page and update all UI to reflect it.
        setCurrentItem(initialGalleryItem!, direction: .forward, shouldAutoPlayVideo: true, animated: false)
        self.initialGalleryItem = nil

        mediaGallery.addDelegate(self)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        setNeedsStatusBarAppearanceUpdate()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass {
            updateControlsForCurrentOrientation()
        }
        if let topBarHeightConstraint {
            topBarHeightConstraint.constant = topBarHeight
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
        super.didReceiveMemoryWarning()
        cachedPages.removeAll()
    }

    // MARK: Paging

    private var cachedPages: [MediaGalleryItem: MediaItemViewController] = [:]

    private func buildGalleryPage(galleryItem: MediaGalleryItem) -> MediaItemViewController {
        if let cachedPage = cachedPages[galleryItem] {
            Logger.debug("cache hit.")
            return cachedPage
        }

        Logger.debug("cache miss.")

        let viewController = MediaItemViewController(galleryItem: galleryItem)
        viewController.delegate = self
        cachedPages[galleryItem] = viewController
        return viewController
    }

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
        shouldAutoPlayVideo: Bool = false,
        animated: Bool
    ) {
        if let previousPage = viewControllers?.first as? MediaItemViewController {
            previousPage.videoPlaybackStatusObserver = nil
            previousPage.zoomOut(animated: false)
            previousPage.stopVideoIfPlaying()
        }

        let mediaPage = buildGalleryPage(galleryItem: item)
        mediaPage.shouldAutoPlayVideo = true
        setViewControllers([mediaPage], direction: direction, animated: animated) { _ in
            self.didTransitionToNewPage(animated: animated)
        }
    }

    private func didTransitionToNewPage(animated: Bool) {
        guard let currentViewController else {
            owsFailBeta("No MediaItemViewController")
            return
        }

        bottomMediaPanel.configureWithMediaItem(
            currentViewController.galleryItem,
            videoPlayer: currentViewController.videoPlayer,
            animated: animated
        )
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.view.layoutIfNeeded()
            }
        }

        updateScreenTitle(using: currentViewController.galleryItem)
        updateContextMenuActions()
        currentViewController.videoPlaybackStatusObserver = bottomMediaPanel
        showOrHideTopAndBottomPanelsAsNecessary(animated: animated)
    }

    // MARK: Show / hide toolbars

    private var _shouldHideToolbars: Bool = false

    private var shouldHideToolbars: Bool {
        get { _shouldHideToolbars }
        set { setShouldHideToolbars(newValue, animated: false) }
    }

    private func setShouldHideToolbars(_ shouldHide: Bool, animated: Bool = false) {
        _shouldHideToolbars = shouldHide
        showOrHideTopAndBottomPanelsAsNecessary(animated: animated)
        setNeedsStatusBarAppearanceUpdate()
    }

    private func showOrHideTopAndBottomPanelsAsNecessary(animated: Bool) {
        topPanel.setIsHidden(shouldHideToolbars, animated: animated)
        bottomMediaPanel.setIsHidden(shouldHideToolbars || bottomMediaPanel.shouldBeHidden, animated: animated)
    }

    private var shouldHideStatusBar: Bool {
        guard !UIDevice.current.isIPad else { return shouldHideToolbars }
        return shouldHideToolbars || traitCollection.verticalSizeClass == .compact
    }

    private func updateControlsForCurrentOrientation() {
        bottomMediaPanel.isLandscapeLayout = traitCollection.verticalSizeClass == .compact

        // Bottom bar might be hidden while in landscape and visible in portrait, for the same media.
        showOrHideTopAndBottomPanelsAsNecessary(animated: false)

        if bottomMediaPanel.isLandscapeLayout {
            // Order of buttons is reversed: first button in array is the outermost in the navbar.
            navigationItem.rightBarButtonItems = [ contextMenuBarButton, barButtonForwardMedia, barButtonShareMedia ]
        } else {
            navigationItem.rightBarButtonItems = [ contextMenuBarButton ]
        }
    }

    // MARK: Context Menu

    private lazy var contextMenuBarButton: UIBarButtonItem = {
        let contextButton = ContextMenuButton()
        contextButton.showsContextMenuAsPrimaryAction = true
        contextButton.forceDarkTheme = true
        return UIBarButtonItem(customView: contextButton)
    }()

    private func updateContextMenuButtonIcon() {
        guard let button = contextMenuBarButton.customView as? UIButton else {
            owsFailDebug("button is nil")
            return
        }
        let imageResourceName = needsCompactToolbars ? "ellipsis-circle-20" : "ellipsis-circle-24"
        let buttonImage = UIImage(imageLiteralResourceName: imageResourceName)
        button.setImage(buttonImage, for: .normal)
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
            title: OWSLocalizedString(
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

    private lazy var barButtonShareMedia = UIBarButtonItem(
        image: UIImage(imageLiteralResourceName: "media-viewer-share-24"),
        landscapeImagePhone: UIImage(imageLiteralResourceName: "media-viewer-share-20"),
        style: .plain,
        target: self,
        action: #selector(didPressShare)
    )

    private lazy var barButtonForwardMedia = UIBarButtonItem(
        image: UIImage(imageLiteralResourceName: "media-viewer-forward-24"),
        landscapeImagePhone: UIImage(imageLiteralResourceName: "media-viewer-forward-20"),
        style: .plain,
        target: self,
        action: #selector(didPressForward)
    )

    // MARK: Helpers

    private func buildChromePanelView() -> UIView {
        let view = UIView()
        view.tintColor = Theme.darkThemePrimaryColor
        view.preservesSuperviewLayoutMargins = true

        let blurEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        let blurBackgroundView = UIVisualEffectView(effect: blurEffect)
        view.addSubview(blurBackgroundView)
        blurBackgroundView.autoPinEdgesToSuperviewEdges()
        return view
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
    private func didPressShare(_ sender: Any) {
        shareCurrentMedia(fromNavigationBar: true)
    }

    /// Forwards all media from the message containing the currently gallery
    /// item.
    ///
    /// Skips any media that we do not have downloaded.
    @objc
    private func didPressForward(_ sender: Any) {
        forwardCurrentMedia()
    }

    private func forwardCurrentMedia() {
        let messageForCurrentItem = currentItem.message

        let mediaAttachments: [TSAttachment] = databaseStorage.read { transaction in
            messageForCurrentItem.bodyAttachments(with: transaction.unwrapGrdbRead)
        }

        let mediaAttachmentStreams: [TSAttachmentStream] = mediaAttachments.compactMap { attachment in
            guard let attachmentStream = attachment as? TSAttachmentStream else {
                // Our current media item should always be an attachment
                // stream (downloaded). However, we can't guarantee that the
                // same is true for other media in the message to forward. For
                // example, another piece of media in this message may have
                // failed to download.
                //
                // If so, we should continue trying to forward the ones we can.

                Logger.warn("Skipping attachment that is not an attachment stream. Did this attachment fail to download?")
                return nil
            }

            return attachmentStream
        }

        let mediaCount = mediaAttachmentStreams.count

        switch mediaCount {
        case 0:
            owsFail("We should always have at least one attachment stream, for the current item.")
        case 1:
            ForwardMessageViewController.present(
                forAttachmentStreams: mediaAttachmentStreams,
                fromMessage: messageForCurrentItem,
                from: self,
                delegate: self
            )
        default:
            // If we are forwarding multiple items, warn the user first.

            let titleFormatString = OWSLocalizedString(
                "MEDIA_PAGE_FORWARD_MEDIA_CONFIRM_TITLE_%d",
                tableName: "PluralAware",
                comment: "Text confirming the user wants to forward media. Embeds {{ %1$@ the number of media to be forwarded }}."
            )

            OWSActionSheets.showConfirmationAlert(
                message: OWSLocalizedString(
                    "MEDIA_PAGE_FORWARD_MEDIA_CONFIRM_MESSAGE",
                    comment: "Text explaining that the user will forward all media from a message."
                ),
                proceedTitle: String.localizedStringWithFormat(
                    titleFormatString,
                    mediaCount
                ),
                proceedAction: { [weak self] _ in
                    guard let self else { return }

                    ForwardMessageViewController.present(
                        forAttachmentStreams: mediaAttachmentStreams,
                        fromMessage: messageForCurrentItem,
                        from: self,
                        delegate: self
                    )
                }
            )
        }
    }

    private func shareCurrentMedia(fromNavigationBar: Bool) {
        guard let currentViewController else { return }
        let attachmentStream = currentViewController.galleryItem.attachmentStream
        let sender = fromNavigationBar ? barButtonShareMedia : bottomMediaPanel
        AttachmentSharing.showShareUI(for: attachmentStream, sender: sender)
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

    // MARK: Dynamic Header

    private func senderName(from message: TSMessage) -> String {
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
        label.font = UIFont.regularFont(ofSize: 17)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    private lazy var headerDateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = UIFont.regularFont(ofSize: 12)
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

    private func updateScreenTitle(using mediaItem: MediaGalleryItem) {
        headerNameLabel.text = senderName(from: mediaItem.message)

        // use sent date
        let date = Date(timeIntervalSince1970: Double(mediaItem.message.timestamp) / 1000)
        headerDateLabel.text = dateFormatter.string(from: date)
    }
}

extension MediaPageViewController: UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted: Bool
    ) {
        if let previousPage = previousViewControllers.first as? MediaItemViewController {
            previousPage.zoomOut(animated: false)
            previousPage.stopVideoIfPlaying()
            previousPage.videoPlaybackStatusObserver = nil
        }

        if transitionCompleted {
            didTransitionToNewPage(animated: true)
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

        return buildGalleryPage(galleryItem: precedingItem)
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

        return buildGalleryPage(galleryItem: nextItem)
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

    func mediaGalleryShouldDeferUpdate(_ mediaGallery: MediaGallery) -> Bool {
        return false
    }
}

extension MediaPageViewController: MediaItemViewControllerDelegate {

    func mediaItemViewControllerDidTapMedia(_ viewController: MediaItemViewController) {
        setShouldHideToolbars(!shouldHideToolbars, animated: true)
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

extension MediaPageViewController: MediaControlPanelDelegate {

    func mediaControlPanelDidRequestForwardMedia(_ panel: MediaControlPanelView) {
        forwardCurrentMedia()
    }

    func mediaControlPanelDidRequestShareMedia(_ panel: MediaControlPanelView) {
        shareCurrentMedia(fromNavigationBar: false)
    }

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
        guard let snapshotView = view.snapshotView(afterScreenUpdates: true) else { return nil }

        // Apply masking to only show top and bottom panels.
        let maskLayer = CAShapeLayer()
        maskLayer.frame = snapshotView.layer.bounds
        let path = UIBezierPath()
        path.append(UIBezierPath(rect: topPanel.frame))
        path.append(UIBezierPath(rect: bottomMediaPanel.frame))
        maskLayer.path = path.cgPath
        snapshotView.layer.mask = maskLayer

        let presentationFrame = coordinateSpace.convert(snapshotView.frame, from: view.superview!)

        return (snapshotView, presentationFrame)
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
