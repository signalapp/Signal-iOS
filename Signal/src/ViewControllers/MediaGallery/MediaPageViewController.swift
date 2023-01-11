//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

// Objc wrapper for the MediaGalleryItem struct
@objc
public class GalleryItemBox: NSObject {
    public let value: MediaGalleryItem

    init(_ value: MediaGalleryItem) {
        self.value = value
    }

    @objc
    public var attachmentStream: TSAttachmentStream {
        return value.attachmentStream
    }
}

fileprivate extension MediaDetailViewController {
    var galleryItem: MediaGalleryItem {
        return self.galleryItemBox.value
    }
}

class MediaPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, MediaDetailViewControllerDelegate, MediaGalleryDelegate, InteractivelyDismissableViewController {

    var mediaInteractiveDismiss: MediaInteractiveDismiss!

    private var cachedPages: [MediaGalleryItem: MediaDetailViewController] = [:]
    private var initialPage: MediaDetailViewController!

    public var currentViewController: MediaDetailViewController {
        return viewControllers!.first as! MediaDetailViewController
    }

    public var currentItem: MediaGalleryItem {
        return currentViewController.galleryItemBox.value
    }

    public func setCurrentItem(_ item: MediaGalleryItem, direction: UIPageViewController.NavigationDirection, animated isAnimated: Bool) {
        guard let galleryPage = self.buildGalleryPage(galleryItem: item) else {
            owsFailDebug("unexpectedly unable to build new gallery page")
            return
        }

        updateTitle(item: item)
        updateCaption(item: item)
        setViewControllers([galleryPage], direction: direction, animated: isAnimated)
        updateFooterBarButtonItems(isPlayingVideo: false)
        updateMediaRail()
    }

    private var mostRecentAlbum: MediaGalleryAlbum?

    private let showingSingleMessage: Bool
    let mediaGallery: MediaGallery

    @objc
    convenience init(initialMediaAttachment: TSAttachment, thread: TSThread) {
        self.init(initialMediaAttachment: initialMediaAttachment,
                  thread: thread,
                  showingSingleMessage: false)
    }

    convenience init(initialMediaAttachment: TSAttachment,
                     thread: TSThread,
                     showingSingleMessage: Bool = false) {
        self.init(initialMediaAttachment: initialMediaAttachment,
                  mediaGallery: MediaGallery(thread: thread),
                  showingSingleMessage: showingSingleMessage)
    }

    init(initialMediaAttachment: TSAttachment, mediaGallery: MediaGallery, showingSingleMessage: Bool = false) {
        self.mediaGallery = mediaGallery
        self.showingSingleMessage = showingSingleMessage

        let kSpacingBetweenItems: CGFloat = 20

        let pageViewOptions: [UIPageViewController.OptionsKey: Any] = [.interPageSpacing: kSpacingBetweenItems]
        super.init(transitionStyle: .scroll,
                   navigationOrientation: .horizontal,
                   options: pageViewOptions)

        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
        dataSource = self
        delegate = self
        transitioningDelegate = self

        Logger.info("will ensureLoadedForDetailView")
        let galleryItem = mediaGallery.ensureLoadedForDetailView(focusedAttachment: initialMediaAttachment)
        Logger.info("ensureLoadedForDetailView done")

        guard let initialItem = galleryItem else {
            owsFailDebug("unexpectedly failed to build initialDetailItem.")
            return
        }

        mediaGallery.addDelegate(self)

        guard let initialPage = buildGalleryPage(galleryItem: initialItem,
                                                 shouldAutoPlayVideo: true) else {
            owsFailDebug("unexpectedly unable to build initial gallery item")
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
        Logger.debug("deinit")
    }

    // MARK: - Subview

    // MARK: Top Bar
    lazy var topContainer = UIView()

    // MARK: Bottom Bar
    lazy var bottomContainer = UIView()
    lazy var footerBar = UIToolbar.clear()
    let captionContainerView: CaptionContainerView = CaptionContainerView()
    var galleryRailView: GalleryRailView = GalleryRailView()

    var pagerScrollView: UIScrollView!

    // MARK: UIViewController overrides

    override var preferredStatusBarStyle: UIStatusBarStyle {
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

        // Navigation

        mediaInteractiveDismiss = MediaInteractiveDismiss(targetViewController: self)
        mediaInteractiveDismiss.addGestureRecognizer(to: view)

        // Even though bars are opaque, we want content to be laid out behind them.
        // The bars might obscure part of the content, but they can easily be hidden by tapping
        // The alternative would be that content would shift when the navbars hide.
        self.extendedLayoutIncludesOpaqueBars = true

        // Get reference to paged content which lives in a scrollView created by the superclass
        // We show/hide this content during presentation
        for view in self.view.subviews {
            if let pagerScrollView = view as? UIScrollView {
                self.pagerScrollView = pagerScrollView
            }
        }

        pagerScrollViewContentOffsetObservation = pagerScrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
            guard let strongSelf = self else { return }
            strongSelf.pagerScrollView(strongSelf.pagerScrollView, contentOffsetDidChange: change)
        }

        // Views

        view.backgroundColor = Theme.darkThemeBackgroundColor

        captionContainerView.delegate = self
        updateCaptionContainerVisibility()

        galleryRailView.delegate = self
        galleryRailView.autoSetDimension(.height, toSize: 72)

        topContainer.backgroundColor = UIColor.ows_black.withAlphaComponent(0.4)

        view.addSubview(topContainer)
        topContainer.autoPinWidthToSuperview()
        topContainer.autoPinEdge(toSuperviewEdge: .top)

        let toolbarHeight: CGFloat = 44

        let fakeNavBar = UIView()
        fakeNavBar.autoSetDimension(.height, toSize: toolbarHeight)
        topContainer.addSubview(fakeNavBar)
        fakeNavBar.autoPinWidthToSuperview()
        fakeNavBar.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        fakeNavBar.autoPinEdge(toSuperviewEdge: .bottom)

        fakeNavBar.addSubview(headerView)
        headerView.autoCenterInSuperview()

        let isRTL = CurrentAppContext().isRTL
        let imageName = isRTL ? "NavBarBackRTL" : "NavBarBack"
        let backButton = UIButton(type: .custom)
        backButton.setTemplateImageName(imageName, tintColor: .white)
        backButton.addTarget(self, action: #selector(didPressDismissButton(_:)), for: .touchUpInside)

        fakeNavBar.addSubview(backButton)
        backButton.autoPinEdge(toSuperviewSafeArea: .leading)
        backButton.autoSetDimensions(to: CGSize(square: toolbarHeight))
        backButton.autoVCenterInSuperview()

        footerBar.tintColor = .white

        bottomContainer.backgroundColor = UIColor.ows_black.withAlphaComponent(0.4)

        let bottomStack = UIStackView(arrangedSubviews: [captionContainerView, galleryRailView, footerBar])
        bottomStack.axis = .vertical
        bottomContainer.addSubview(bottomStack)
        bottomStack.autoPinEdgesToSuperviewEdges()

        self.view.addSubview(bottomContainer)
        bottomContainer.autoPinWidthToSuperview()
        bottomContainer.autoPinEdge(toSuperviewEdge: .bottom)
        footerBar.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        footerBar.autoSetDimension(.height, toSize: toolbarHeight)

        updateTitle()
        updateCaption(item: currentItem)
        updateMediaRail()
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

            setNeedsStatusBarAppearanceUpdate()

            currentViewController.setShouldHideToolbars(shouldHideToolbars)
            bottomContainer.isHidden = shouldHideToolbars
            topContainer.isHidden = shouldHideToolbars
        }
    }

    private var shouldHideStatusBar: Bool {
        guard !UIDevice.current.isIPad else { return shouldHideToolbars }

        return shouldHideToolbars || CurrentAppContext().interfaceOrientation.isLandscape
    }

    // MARK: Bar Buttons

    lazy var shareBarButton: UIBarButtonItem = {
        let image = #imageLiteral(resourceName: "share-outline-24")
        let shareBarButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(didPressShare))
        shareBarButton.tintColor = Theme.darkThemePrimaryColor
        return shareBarButton
    }()

    lazy var forwardBarButton: UIBarButtonItem = {
        let image = #imageLiteral(resourceName: "forward-solid-24")
        let forwardBarButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(didPressForward))
        forwardBarButton.tintColor = Theme.darkThemePrimaryColor
        return forwardBarButton
    }()

    lazy var deleteBarButton: UIBarButtonItem = {
        let image = #imageLiteral(resourceName: "trash-solid-24")
        let deleteBarButton = UIBarButtonItem(image: image,
                                              style: .plain,
                                              target: self,
                                              action: #selector(didPressDelete))
        deleteBarButton.tintColor = Theme.darkThemePrimaryColor
        return deleteBarButton
    }()

    func buildFlexibleSpace() -> UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    }

    lazy var videoPlayBarButton: UIBarButtonItem = {
        let videoPlayBarButton = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(didPressPlayBarButton))
        videoPlayBarButton.tintColor = Theme.darkThemePrimaryColor
        return videoPlayBarButton
    }()

    lazy var videoPauseBarButton: UIBarButtonItem = {
        let videoPauseBarButton = UIBarButtonItem(barButtonSystemItem: .pause, target: self, action:
                                                    #selector(didPressPauseBarButton))
        videoPauseBarButton.tintColor = Theme.darkThemePrimaryColor
        return videoPauseBarButton
    }()

    private func updateFooterBarButtonItems(isPlayingVideo: Bool) {
        var toolbarItems: [UIBarButtonItem] = [
            shareBarButton,
            buildFlexibleSpace(),
            forwardBarButton,
            buildFlexibleSpace()
        ]

        if self.currentItem.isVideo {
            toolbarItems += [
                isPlayingVideo ? self.videoPauseBarButton : self.videoPlayBarButton,
                buildFlexibleSpace()
            ]
        }

        toolbarItems.append(deleteBarButton)

        self.footerBar.setItems(toolbarItems, animated: false)
    }

    func updateMediaRail() {
        if mostRecentAlbum?.items.contains(currentItem) != true {
            mostRecentAlbum = mediaGallery.album(for: currentItem)
        }

        galleryRailView.configureCellViews(itemProvider: mostRecentAlbum!,
                                           focusedItem: currentItem,
                                           cellViewBuilder: { _ in return GalleryRailCellView() })
    }

    // MARK: Actions

    @objc
    public func didSwipeView(sender: Any) {
        Logger.debug("")

        self.dismissSelf(animated: true)
    }

    @objc
    public func didPressDismissButton(_ sender: Any) {
        dismissSelf(animated: true)
    }

    @objc
    public func performInteractiveDismissal(animated: Bool) {
        dismissSelf(animated: true)
    }

    @objc
    public func didPressShare(_ sender: UIBarButtonItem) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }

        let attachmentStream = currentViewController.galleryItem.attachmentStream

        AttachmentSharing.showShareUI(forAttachment: attachmentStream, sender: sender)
    }

    @objc
    public func didPressForward(_ sender: Any) {
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

    @objc
    public func didPressDelete(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }

        let actionSheet = ActionSheetController(title: nil, message: nil)
        let deleteAction = ActionSheetAction(title: CommonStrings.deleteButton,
                                             style: .destructive) { _ in
            let deletedItem = currentViewController.galleryItem
            self.mediaGallery.delete(items: [deletedItem], initiatedBy: self)
        }
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(deleteAction)

        self.presentActionSheet(actionSheet)
    }

    // MARK: MediaGalleryDelegate

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

        if showingSingleMessage {
            // In message details, which doesn't use the slider, so don't swap pages.
        } else if let nextItem = mediaGallery.galleryItem(after: currentItem) {
            self.setCurrentItem(nextItem, direction: .forward, animated: isAnimated)
        } else if let previousItem = mediaGallery.galleryItem(before: currentItem) {
            self.setCurrentItem(previousItem, direction: .reverse, animated: isAnimated)
        } else {
            // else we deleted the last piece of media, return to the conversation view
            self.dismissSelf(animated: true)
        }
    }

    func itemIsAllowed(_ item: MediaGalleryItem) -> Bool {
        // Normally, we can show any media item, but if we're limited
        // to showing a single message, don't page beyond that message
        return !showingSingleMessage || currentItem.message == item.message
    }

    func mediaGallery(_ mediaGallery: MediaGallery, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        // Either this is an internal deletion, in which case willDelete would have been called already,
        // or it's an external deletion, in which case didReloadItemsInSection would have been called already.
    }

    func mediaGallery(_ mediaGallery: MediaGallery, didReloadItemsInSections sections: IndexSet) {
        self.didReloadAllSectionsInMediaGallery(mediaGallery)
    }

    func didAddSectionInMediaGallery(_ mediaGallery: MediaGallery) {
        // Does not affect the current item.
    }

    func didReloadAllSectionsInMediaGallery(_ mediaGallery: MediaGallery) {
        let attachment = self.currentItem.attachmentStream
        guard let reloadedItem = mediaGallery.ensureLoadedForDetailView(focusedAttachment: attachment) else {
            // Assume the item was deleted.
            self.dismissSelf(animated: true)
            return
        }
        self.setCurrentItem(reloadedItem, direction: .forward, animated: false)
    }

    @objc
    public func didPressPlayBarButton(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressPlayBarButton(sender)
    }

    @objc
    public func didPressPauseBarButton(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressPauseBarButton(sender)
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

            if
                let pendingCaptionText = pendingViewController.galleryItem.captionForDisplay,
                !pendingCaptionText.isEmpty {
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
                if previousPage != currentViewController {
                    captionContainerView.completePagerTransition()
                }

                updateTitle()
                updateMediaRail()
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
        Logger.debug("")

        guard let previousDetailViewController = viewController as? MediaDetailViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        let previousItem = previousDetailViewController.galleryItem
        guard let nextItem: MediaGalleryItem = mediaGallery.galleryItem(before: previousItem), itemIsAllowed(nextItem) else {
            return nil
        }

        guard let nextPage: MediaDetailViewController = buildGalleryPage(galleryItem: nextItem) else {
            return nil
        }

        return nextPage
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("")

        guard let previousDetailViewController = viewController as? MediaDetailViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        let previousItem = previousDetailViewController.galleryItem
        guard let nextItem = mediaGallery.galleryItem(after: previousItem), itemIsAllowed(nextItem) else {
            // no more pages
            return nil
        }

        guard let nextPage: MediaDetailViewController = buildGalleryPage(galleryItem: nextItem) else {
            return nil
        }

        return nextPage
    }

    private func buildGalleryPage(galleryItem: MediaGalleryItem,
                                  shouldAutoPlayVideo: Bool = false) -> MediaDetailViewController? {

        if let cachedPage = cachedPages[galleryItem] {
            Logger.debug("cache hit.")
            return cachedPage
        }

        Logger.debug("cache miss.")

        let viewController = MediaDetailViewController(galleryItemBox: GalleryItemBox(galleryItem),
                                                       shouldAutoPlayVideo: shouldAutoPlayVideo)
        viewController.delegate = self

        cachedPages[galleryItem] = viewController
        return viewController
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

    public func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
        currentViewController.zoomOut(animated: true)

        currentViewController.stopAnyVideo()
        self.navigationController?.setNavigationBarHidden(false, animated: false)

        dismiss(animated: isAnimated, completion: completion)
    }

    // MARK: MediaDetailViewControllerDelegate

    @objc
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

    lazy private var headerNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = UIFont.ows_regularFont(withSize: 17)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    lazy private var headerDateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = UIFont.ows_regularFont(withSize: 12)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    private lazy var headerView: UIView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 0
        stackView.distribution = .fillProportionally
        stackView.addArrangedSubview(headerNameLabel)
        stackView.addArrangedSubview(headerDateLabel)

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

extension MediaGalleryItem: GalleryRailItem {
    public func buildRailItemView() -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.image = getRailImage()
        return imageView
    }

    public func getRailImage() -> UIImage? {
        return self.thumbnailImageSync()
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

        self.setCurrentItem(targetItem, direction: direction, animated: true)
    }
}

extension MediaPageViewController: CaptionContainerViewDelegate {

    func captionContainerViewDidUpdateText(_ captionContainerView: CaptionContainerView) {
        updateCaptionContainerVisibility()
    }

    // MARK: Helpers

    func updateCaptionContainerVisibility() {
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
        let mediaView = currentViewController.mediaView

        guard nil != mediaView.superview else {
            owsFailDebug("superview was unexpectedly nil")
            return nil
        }

        // TODO better match the corner radius
        return MediaPresentationContext(mediaView: mediaView, presentationFrame: mediaView.frame, cornerRadius: 0)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        view.layoutIfNeeded()

        guard let bottomSnapshot = bottomContainer.snapshotView(afterScreenUpdates: true) else {
            owsFailDebug("bottomSnapshot was unexpectedly nil")
            return nil
        }

        guard let topSnapshot = topContainer.snapshotView(afterScreenUpdates: true) else {
            owsFailDebug("topSnapshot was unexpectedly nil")
            return nil
        }

        let snapshot = UIView(frame: view.frame)
        snapshot.addSubview(topSnapshot)
        topSnapshot.frame = topContainer.frame

        snapshot.addSubview(bottomSnapshot)
        bottomSnapshot.frame = bottomContainer.frame

        let presentationFrame = coordinateSpace.convert(snapshot.frame,
                                                        from: view.superview!)

        return (snapshot, presentationFrame)
    }
}

extension MediaPageViewController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController,
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
            owsFailDebug("unexpected presented: \(dismissed)")
            return nil
        }

        guard let mediaInteractiveDismiss = mediaInteractiveDismiss else {
            // We can't do a media dismiss (probably the item was externally deleted).
            return nil
        }

        let animationController = MediaDismissAnimationController(galleryItem: currentItem,
                                                                  interactionController: mediaInteractiveDismiss)
        mediaInteractiveDismiss.interactiveDismissDelegate = animationController

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

// MARK: -

extension MediaPageViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(items: [ForwardMessageItem],
                                              recipientThreads: [TSThread]) {
        dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(items: items,
                                                         recipientThreads: recipientThreads,
                                                         fromViewController: self)
        }
    }

    public func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }
}
