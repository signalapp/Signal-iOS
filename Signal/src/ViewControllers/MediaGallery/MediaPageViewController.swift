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
    private lazy var bottomPanelStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ captionView, galleryRailView, footerBar ])
        stackView.axis = .vertical
        stackView.preservesSuperviewLayoutMargins = true
        return stackView
    }()
    private lazy var footerBar: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ buttonShareMedia, buttonForwardMedia ])
        stackView.axis = .horizontal
        stackView.distribution = .equalSpacing
        stackView.spacing = 32
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.tintColor = Theme.darkThemePrimaryColor
        return stackView
    }()
    private var footerBarHeight: CGFloat { topBarHeight }
    private var footerBarHeightConstraint: NSLayoutConstraint?

    private lazy var captionView = MediaCaptionView()
    private lazy var galleryRailView: GalleryRailView = {
        let view = GalleryRailView()
        view.delegate = self
        view.itemSize = 40
        view.layoutMargins.bottom = 12
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

        // Bottom bar
        view.addSubview(bottomPanel)
        bottomPanel.autoPinWidthToSuperview()
        bottomPanel.autoPinEdge(toSuperviewEdge: .bottom)

        bottomPanel.addSubview(bottomPanelStackView)
        bottomPanelStackView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        bottomPanelStackView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        // Buttons have some margins around their icons. Adjust stack view leading and trailing margin
        // so that button icons are aligned to everything else. 
        footerBar.layoutMargins.leading = OWSTableViewController2.defaultHOuterMargin - buttonShareMedia.contentEdgeInsets.leading
        footerBar.layoutMargins.trailing = OWSTableViewController2.defaultHOuterMargin - buttonForwardMedia.contentEdgeInsets.leading
        footerBarHeightConstraint = footerBar.autoSetDimension(.height, toSize: footerBarHeight)

        updateTitle()
        updateCaption()
        updateMediaRail(animated: false)
        updateMediaControls()
        updateBottomPanelVisibility()
        updateContextMenuButtonIcon()

        // Gestures
        let verticalSwipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeView))
        verticalSwipe.direction = [.up, .down]
        view.addGestureRecognizer(verticalSwipe)

        captionView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleCaptionBoxIsExpanded)))
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        setNeedsStatusBarAppearanceUpdate()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass {
            updateMediaRail(animated: false)
            updateMediaControls()
            updateBottomPanelVisibility()
        }
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

        setViewControllers([galleryPage], direction: direction, animated: isAnimated)
        updateTitle()
        updateCaption()
        updateMediaRail(animated: isAnimated)
        updateMediaControls()
        updateBottomPanelVisibility()
    }

    private var mostRecentAlbum: MediaGalleryAlbum?

    // MARK: KVO

    private var pagerScrollViewContentOffsetObservation: NSKeyValueObservation?
    private func pagerScrollView(_ pagerScrollView: UIScrollView, contentOffsetDidChange change: NSKeyValueObservedChange<CGPoint>) {
        guard let newValue = change.newValue else {
            owsFailDebug("newValue was unexpectedly nil")
            return
        }

        guard pagerScrollView.isTracking || pagerScrollView.isDecelerating else { return }

        let width = pagerScrollView.frame.width
        guard width > 0 else { return }
        let ratioComplete = abs((newValue.x - width) / width)
        captionView.updateTransitionProgress(ratioComplete)
    }

    // MARK: View Helpers

    private var shouldHideToolbars: Bool = false {
        didSet {
            guard oldValue != shouldHideToolbars else { return }

            setNeedsStatusBarAppearanceUpdate()

            bottomPanel.isHidden = shouldHideToolbars
            topPanel.isHidden = shouldHideToolbars
        }
    }

    private var shouldHideStatusBar: Bool {
        guard !UIDevice.current.isIPad else { return shouldHideToolbars }

        return shouldHideToolbars || traitCollection.verticalSizeClass == .compact
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

    private lazy var barButtonShareMedia = UIBarButtonItem(
        image: UIImage(imageLiteralResourceName: "share-outline-24"),
        landscapeImagePhone: UIImage(imageLiteralResourceName: "share-outline-20"),
        style: .plain,
        target: self,
        action: #selector(didPressShare)
    )

    private lazy var buttonShareMedia: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "share-outline-24"), for: .normal)
        button.addTarget(self, action: #selector(didPressShare), for: .touchUpInside)
        button.contentVerticalAlignment = .center
        button.contentHorizontalAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(margin: 8)
        button.autoPin(toAspectRatio: 1)
        return button
    }()

    private lazy var barButtonForwardMedia = UIBarButtonItem(
        image: UIImage(imageLiteralResourceName: "forward-outline-24"),
        landscapeImagePhone: UIImage(imageLiteralResourceName: "forward-outline-20"),
        style: .plain,
        target: self,
        action: #selector(didPressForward)
    )

    private lazy var buttonForwardMedia: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "forward-outline-24"), for: .normal)
        button.addTarget(self, action: #selector(didPressForward), for: .touchUpInside)
        button.contentVerticalAlignment = .center
        button.contentHorizontalAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(margin: 8)
        button.autoPin(toAspectRatio: 1)
        return button
    }()

    private var videoPlaybackControlView: VideoPlaybackControlView?
    private var videoPlayerProgressViewPortrait: PlayerProgressView?
    private var videoPlayerProgressViewLandscape: PlayerProgressView?

    private func hidePlayerProgressViewPortrait() {
        guard let videoPlayerProgressViewPortrait else { return }
        videoPlayerProgressViewPortrait.videoPlayer = nil
        videoPlayerProgressViewPortrait.superview?.isHiddenInStackView = true
    }

    private func hidePlayerProgressViewLandscape() {
        guard let videoPlayerProgressViewLandscape else { return }
        videoPlayerProgressViewLandscape.videoPlayer = nil
        videoPlayerProgressViewLandscape.isHiddenInStackView = true
    }

    private func updateMediaControls() {
        guard let currentViewController, let currentItem else { return }

        let isLandscapeLayout = traitCollection.verticalSizeClass == .compact

        // Context menu actions are dependent on current media type.
        updateContextMenuActions()

        // Move Forward and Share to the navigation bar when in landscape.
        if isLandscapeLayout {
            // Order of buttons is reversed.
            navigationItem.rightBarButtonItems = [ contextMenuBarButton, barButtonForwardMedia, barButtonShareMedia ]
        } else {
            navigationItem.rightBarButtonItems = [ contextMenuBarButton ]
        }

        // Update controls in the bottom panel.
        if currentItem.isVideo, let videoPlayer = currentViewController.videoPlayer {
            footerBar.isHiddenInStackView = false
            buttonShareMedia.isHiddenInStackView = isLandscapeLayout
            buttonForwardMedia.isHiddenInStackView = isLandscapeLayout

            // Lazily create `videoPlaybackControlView` and put it into the `footerBar` - it'll have a permanent place there.
            let videoPlaybackControlView: VideoPlaybackControlView
            if let existingPlaybackControlView = self.videoPlaybackControlView {
                videoPlaybackControlView = existingPlaybackControlView
            } else {
                videoPlaybackControlView = VideoPlaybackControlView()
                footerBar.insertArrangedSubview(videoPlaybackControlView, at: 1) // between Share and Forward
                self.videoPlaybackControlView = videoPlaybackControlView
            }
            videoPlaybackControlView.isHiddenInStackView = false
            videoPlaybackControlView.isLandscapeLayout = isLandscapeLayout
            videoPlaybackControlView.videoPlayer = videoPlayer
            videoPlaybackControlView.updateWithMediaItem(currentItem)
            videoPlaybackControlView.registerWithVideoPlaybackStatusProvider(currentViewController)

            // Lazily create player progress view and attach it to the video player.
            // Also hide progress view that is not used in the current orientation.
            let playerProgressView: PlayerProgressView
            if isLandscapeLayout {
                hidePlayerProgressViewPortrait()

                if let existingProgressView = videoPlayerProgressViewLandscape {
                    playerProgressView = existingProgressView
                    playerProgressView.isHiddenInStackView = false
                } else {
                    playerProgressView = PlayerProgressView(forVerticallyCompactLayout: true)
                    self.videoPlayerProgressViewLandscape = playerProgressView

                    footerBar.addArrangedSubview(playerProgressView)
                }
            } else {
                hidePlayerProgressViewLandscape()

                if let existingProgressView = videoPlayerProgressViewPortrait {
                    playerProgressView = existingProgressView
                    playerProgressView.superview?.isHiddenInStackView = false
                } else {
                    playerProgressView = PlayerProgressView(forVerticallyCompactLayout: false)
                    self.videoPlayerProgressViewPortrait = playerProgressView

                    let containerView = UIView()
                    containerView.preservesSuperviewLayoutMargins = true
                    containerView.addSubview(playerProgressView)
                    playerProgressView.autoPinWidthToSuperviewMargins()
                    playerProgressView.autoPinEdge(toSuperviewEdge: .top, withInset: 14)
                    playerProgressView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
                    bottomPanelStackView.insertArrangedSubview(containerView, at: 1)
                }
            }
            playerProgressView.videoPlayer = videoPlayer
        } else {
            // In landscape we hide the entire view that contains Share and Forward buttons, video playback controls.
            buttonShareMedia.isHiddenInStackView = false
            buttonForwardMedia.isHiddenInStackView = false
            footerBar.isHiddenInStackView = isLandscapeLayout

            // No video player - hide controls.
            if let videoPlaybackControlView {
                videoPlaybackControlView.isHiddenInStackView = true
                videoPlaybackControlView.videoPlayer = nil
                videoPlaybackControlView.registerWithVideoPlaybackStatusProvider(nil)
            }

            // No video player - hide progress bar.
            hidePlayerProgressViewPortrait()
            hidePlayerProgressViewLandscape() // this is not necessary visually, but it does disconnect progress bar from video player.
        }
    }

    func updateBottomPanelVisibility() {
        // Do nothing if toolbars are hidden by user.
        guard !shouldHideToolbars else { return }

        let animateChanges = view.window != nil
        if traitCollection.verticalSizeClass == .compact {
            let noCaption = captionView.text.isEmptyOrNil
            let mediaRailHidden = galleryRailView.isHiddenInStackView
            let videoPlaybackControlsHidden = videoPlaybackControlView?.isHiddenInStackView ?? true
            bottomPanel.setIsHidden(noCaption && mediaRailHidden && videoPlaybackControlsHidden, animated: animateChanges)
        } else {
            bottomPanel.setIsHidden(false, animated: animateChanges)
        }
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

        let isLandscapeLayout = traitCollection.verticalSizeClass == .compact
        galleryRailView.layoutMargins.top = captionView.text.isEmptyOrNil ? 20 : 4
        galleryRailView.hidesAutomatically = !isLandscapeLayout
        galleryRailView.configureCellViews(
            itemProvider: mostRecentAlbum!,
            focusedItem: currentItem,
            cellViewBuilder: { _ in
                return GalleryRailCellView(configuration: MediaPageViewController.galleryCellConfiguration)
            },
            animated: animated
        )
        if isLandscapeLayout {
            galleryRailView.isHiddenInStackView = true
        }
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

    /// Forwards all media from the message containing the currently gallery
    /// item.
    ///
    /// Skips any media that we do not have downloaded.
    @objc
    private func didPressForward(_ sender: Any) {
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
        guard let item = currentItem else { return }

        let name = senderName(message: item.message)
        headerNameLabel.text = name

        // use sent date
        let date = Date(timeIntervalSince1970: Double(item.message.timestamp) / 1000)
        headerDateLabel.text = dateFormatter.string(from: date)
    }

    // MARK: Caption Box

    private func updateCaption() {
        captionView.text = currentItem.captionForDisplay
    }

    @objc
    private func toggleCaptionBoxIsExpanded(_ gestureRecognizer: UITapGestureRecognizer) {
        guard !captionView.isTransitionInProgress, captionView.canBeExpanded else { return }

        let animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 0.645, springResponse: 0.25)
        animator.addAnimations {
            self.captionView.isExpanded = !self.captionView.isExpanded
            self.view.layoutIfNeeded()
        }
        animator.startAnimation()
    }
}

extension MediaPageViewController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        Logger.debug("")

        owsAssert(pendingViewControllers.count == 1)
        guard let pendingViewController = pendingViewControllers.first as? MediaItemViewController else {
            owsFailDebug("unexpected transition to: \(pendingViewControllers)")
            return
        }

        captionView.beginInteractiveTransition(text: pendingViewController.galleryItem.captionForDisplay?.nilIfEmpty)
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

        captionView.finishInteractiveTransition(transitionCompleted)

        if transitionCompleted {
            previousPage.zoomOut(animated: false)
            previousPage.stopVideoIfPlaying()

            updateTitle()
            updateMediaRail(animated: true)
            updateMediaControls()
            updateBottomPanelVisibility()
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
