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

    @objc
    public var attachmentStream: TSAttachmentStream {
        return value.attachmentStream
    }
}

private class Box<A> {
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

class MediaPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, MediaDetailViewControllerDelegate, MediaGalleryDataSourceDelegate {

    private weak var mediaGalleryDataSource: MediaGalleryDataSource?

    private var cachedPages: [MediaGalleryItem: MediaDetailViewController] = [:]
    private var initialPage: MediaDetailViewController!

    public var currentViewController: MediaDetailViewController {
        return viewControllers!.first as! MediaDetailViewController
    }

    public var currentItem: MediaGalleryItem! {
        get {
            return currentViewController.galleryItemBox.value
        }
        set {
            setCurrentItem(newValue, direction: .forward, animated: false)
        }
    }

    private func setCurrentItem(_ item: MediaGalleryItem, direction: UIPageViewControllerNavigationDirection, animated isAnimated: Bool) {
        guard let galleryPage = self.buildGalleryPage(galleryItem: item) else {
            owsFailDebug("unexpetedly unable to build new gallery page")
            return
        }

        self.updateTitle(item: item)
        self.setViewControllers([galleryPage], direction: direction, animated: isAnimated)
        self.updateFooterBarButtonItems(isPlayingVideo: false)
    }

    private let uiDatabaseConnection: YapDatabaseConnection

    private let showAllMediaButton: Bool
    private let sliderEnabled: Bool

    private let headerView: UIView

    init(initialItem: MediaGalleryItem, mediaGalleryDataSource: MediaGalleryDataSource, uiDatabaseConnection: YapDatabaseConnection, options: MediaGalleryOption) {
        assert(uiDatabaseConnection.isInLongLivedReadTransaction())
        self.uiDatabaseConnection = uiDatabaseConnection
        self.showAllMediaButton = options.contains(.showAllMediaButton)
        self.sliderEnabled = options.contains(.sliderEnabled)
        self.mediaGalleryDataSource = mediaGalleryDataSource

        let kSpacingBetweenItems: CGFloat = 20

        self.headerView = UIView()
        headerView.layoutMargins = UIEdgeInsets(top: 2, left: 8, bottom: 4, right: 8)

        super.init(transitionStyle: .scroll,
                   navigationOrientation: .horizontal,
                   options: [UIPageViewControllerOptionInterPageSpacingKey: kSpacingBetweenItems])

        let headerStackView = UIStackView()
        headerView.addSubview(headerStackView)

        headerStackView.axis = .vertical
        headerStackView.alignment = .center
        headerStackView.spacing = 0
        headerStackView.distribution = .fillProportionally
        headerStackView.addArrangedSubview(headerNameLabel)
        headerStackView.addArrangedSubview(headerDateLabel)

        headerStackView.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        headerStackView.autoPinEdge(toSuperviewMargin: .right, relation: .greaterThanOrEqual)
        headerStackView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        headerStackView.autoPinEdge(toSuperviewMargin: .left, relation: .greaterThanOrEqual)
        headerStackView.setContentHuggingHigh()
        headerStackView.autoCenterInSuperview()

        self.dataSource = self
        self.delegate = self

        guard let initialPage = self.buildGalleryPage(galleryItem: initialItem) else {
            owsFailDebug("unexpetedly unable to build initial gallery item")
            return
        }
        self.initialPage = initialPage
        self.setViewControllers([initialPage], direction: .forward, animated: false, completion: nil)
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder: NSCoder) {
        notImplemented()
    }

    deinit {
        Logger.debug("deinit")
    }

    var footerBar: UIToolbar!
    var videoPlayBarButton: UIBarButtonItem!
    var videoPauseBarButton: UIBarButtonItem!
    var pagerScrollView: UIScrollView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Navigation

        // Note: using a custom leftBarButtonItem breaks the interactive pop gesture, but we don't want to be able
        // to swipe to go back in the pager view anyway, instead swiping back should show the next page.
        let backButton = OWSViewController.createOWSBackButton(withTarget: self, selector: #selector(didPressDismissButton))
        self.navigationItem.leftBarButtonItem = backButton

        self.navigationItem.titleView = headerView
        self.updateTitle()

        if showAllMediaButton {
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
        pagerScrollView.isScrollEnabled = sliderEnabled

        self.title = "Attachment"

        // Views

        let kFooterHeight: CGFloat = 44

        view.backgroundColor = Theme.backgroundColor

        let footerBar = UIToolbar()
        self.footerBar = footerBar

        self.videoPlayBarButton = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(didPressPlayBarButton))
        self.videoPauseBarButton = UIBarButtonItem(barButtonSystemItem: .pause, target: self, action: #selector(didPressPauseBarButton))

        self.updateFooterBarButtonItems(isPlayingVideo: true)
        self.view.addSubview(footerBar)
        footerBar.autoPinWidthToSuperview()
        footerBar.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        footerBar.autoSetDimension(.height, toSize: kFooterHeight)

        // Gestures

        let verticalSwipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeView))
        verticalSwipe.direction = [.up, .down]
        view.addGestureRecognizer(verticalSwipe)
    }

    override func didReceiveMemoryWarning() {
        Logger.info("")
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
        Logger.debug("")

        currentViewController.stopAnyVideo()

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return
        }
        mediaGalleryDataSource.showAllMedia(focusedItem: currentItem)
    }

    @objc
    public func didSwipeView(sender: Any) {
        Logger.debug("")

        self.dismissSelf(animated: true)
    }

    private var shouldHideToolbars: Bool = false {
        didSet {
            if (oldValue == shouldHideToolbars) {
                return
            }

            // Hiding the status bar affects the positioning of the navbar. We don't want to show that in an animation, it's
            // better to just have everythign "flit" in/out.
            UIApplication.shared.setStatusBarHidden(shouldHideToolbars, with: .none)
            self.navigationController?.setNavigationBarHidden(shouldHideToolbars, animated: false)

            // We don't animate the background color change because the old color shows through momentarily
            // behind where the status bar "used to be".
            self.view.backgroundColor = (shouldHideToolbars ? UIColor.black : Theme.backgroundColor)

            UIView.animate(withDuration: 0.1) {
                self.currentViewController.setShouldHideToolbars(self.shouldHideToolbars)
                self.footerBar.isHidden = self.shouldHideToolbars
            }
        }
    }

    private func updateFooterBarButtonItems(isPlayingVideo: Bool) {
        // TODO do we still need this? seems like a vestige
        // from when media detail view was used for attachment approval
        if self.footerBar == nil {
            owsFailDebug("No footer bar visible.")
            return
        }

        var toolbarItems: [UIBarButtonItem] = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(didPressShare)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        ]

        if (self.currentItem.isVideo) {
            toolbarItems += [
                isPlayingVideo ? self.videoPauseBarButton : self.videoPlayBarButton,
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            ]
        }

        toolbarItems.append(UIBarButtonItem(barButtonSystemItem: .trash,
                                            target: self,
                                            action: #selector(didPressDelete)))

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
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressShare(sender)
    }

    @objc
    public func didPressDelete(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return
        }

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let deleteAction = UIAlertAction(title: NSLocalizedString("TXT_DELETE_TITLE", comment: ""),
                                         style: .destructive) { _ in
                                            let deletedItem = currentViewController.galleryItem
                                            mediaGalleryDataSource.delete(items: [deletedItem], initiatedBy: self)
        }
        actionSheet.addAction(OWSAlerts.cancelAction)
        actionSheet.addAction(deleteAction)

        self.present(actionSheet, animated: true)
    }

    // MARK: MediaGalleryDataSourceDelegate

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, willDelete items: [MediaGalleryItem], initiatedBy: MediaGalleryDataSourceDelegate) {
        Logger.debug("")

        guard let currentItem = self.currentItem else {
              owsFailDebug("currentItem was unexpectedly nil")
            return
        }

        guard items.contains(currentItem) else {
            Logger.debug("irrelevant item")
            return
        }

        // If we setCurrentItem with (animated: true) while this VC is in the background, then
        // the next/previous cache isn't expired, and we're able to swipe back to the just-deleted vc.
        // So to get the correct behavior, we should only animate these transitions when this
        // vc is in the foreground
        let isAnimated = initiatedBy === self

        if !self.sliderEnabled {
            // In message details, which doesn't use the slider, so don't swap pages.
        } else if let nextItem = mediaGalleryDataSource.galleryItem(after: currentItem) {
            self.setCurrentItem(nextItem, direction: .forward, animated: isAnimated)
        } else if let previousItem = mediaGalleryDataSource.galleryItem(before: currentItem) {
            self.setCurrentItem(previousItem, direction: .reverse, animated: isAnimated)
        } else {
            // else we deleted the last piece of media, return to the conversation view
            self.dismissSelf(animated: true)
        }
    }

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        // no-op
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

    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        Logger.debug("")

        assert(pendingViewControllers.count == 1)
        pendingViewControllers.forEach { viewController in
            guard let pendingPage = viewController as? MediaDetailViewController else {
                owsFailDebug("unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Ensure upcoming page respects current toolbar status
            pendingPage.setShouldHideToolbars(self.shouldHideToolbars)
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
                updateTitle()
                previousPage.zoomOut(animated: false)
                previousPage.stopAnyVideo()
                updateFooterBarButtonItems(isPlayingVideo: false)
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

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
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
        Logger.debug("")

        guard let previousDetailViewController = viewController as? MediaDetailViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
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
            Logger.debug("cache hit.")
            return cachedPage
        }

        Logger.debug("cache miss.")
        var fetchedItem: ConversationViewItem?
        self.uiDatabaseConnection.read { transaction in
            let message = galleryItem.message
            let thread = message.thread(with: transaction)
            let conversationStyle = ConversationStyle(thread: thread)
            fetchedItem = ConversationInteractionViewItem(interaction: message,
                                                          isGroupThread: thread.isGroupThread(),
                                                          transaction: transaction,
                                                          conversationStyle: conversationStyle)
        }

        guard let viewItem = fetchedItem else {
            owsFailDebug("viewItem was unexpectedly nil")
            return nil
        }

        let viewController = MediaDetailViewController(galleryItemBox: GalleryItemBox(galleryItem), viewItem: viewItem)
        viewController.delegate = self

        cachedPages[galleryItem] = viewController
        return viewController
    }

    public func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
        // currentVC
        currentViewController.zoomOut(animated: true)
        currentViewController.stopAnyVideo()

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: true)

            return
        }

        mediaGalleryDataSource.dismissMediaDetailViewController(self, animated: isAnimated, completion: completion)
    }

    // MARK: MediaDetailViewControllerDelegate

    @objc
    public func mediaDetailViewControllerDidTapMedia(_ mediaDetailViewController: MediaDetailViewController) {
        Logger.debug("")

        self.shouldHideToolbars = !self.shouldHideToolbars
    }

    public func mediaDetailViewController(_ mediaDetailViewController: MediaDetailViewController, requestDelete conversationViewItem: ConversationViewItem) {
        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: true)

            return
        }

        guard let message = conversationViewItem.interaction as? TSMessage else {
            owsFailDebug("unexpected interaction: \(type(of: conversationViewItem))")
            self.presentingViewController?.dismiss(animated: true)

            return
        }

        guard let galleryItem = self.mediaGalleryDataSource?.galleryItems.first(where: { $0.message == message }) else {
            owsFailDebug("unexpected interaction: \(type(of: conversationViewItem))")
            self.presentingViewController?.dismiss(animated: true)

            return
        }

        dismissSelf(animated: true) {
            mediaGalleryDataSource.delete(items: [galleryItem], initiatedBy: self)
        }
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

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private func senderName(message: TSMessage) -> String {
        switch message {
        case let incomingMessage as TSIncomingMessage:
            return self.contactsManager.displayName(forPhoneIdentifier: incomingMessage.authorId)
        case is TSOutgoingMessage:
            return NSLocalizedString("MEDIA_GALLERY_SENDER_NAME_YOU", comment: "Short sender label for media sent by you")
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
        label.textColor = Theme.navbarTitleColor
        label.font = UIFont.ows_regularFont(withSize: 17)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    lazy private var headerDateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.navbarTitleColor
        label.font = UIFont.ows_regularFont(withSize: 12)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    private func updateTitle() {
        guard let currentItem = self.currentItem else {
            owsFailDebug("currentItem was unexpectedly nil")
            return
        }
        updateTitle(item: currentItem)
    }

    private func updateTitle(item: MediaGalleryItem) {
        let name = senderName(message: item.message)
        headerNameLabel.text = name

        // use sent date
        let date = Date(timeIntervalSince1970: Double(item.message.timestamp) / 1000)
        let formattedDate = dateFormatter.string(from: date)
        headerDateLabel.text = formattedDate

        if #available(iOS 11, *) {
            // Do nothing, on iOS11, autolayout grows the stack view as necessary.
        } else {
            // Size the titleView to be large enough to fit the widest label,
            // but no larger. If we go for a "full width" label, our title view
            // will not be centered (since the left and right bar buttons have different widths)            
            headerNameLabel.sizeToFit()
            headerDateLabel.sizeToFit()
            let maxWidth = max(headerNameLabel.frame.width, headerDateLabel.frame.width)

            let headerFrame: CGRect = CGRect(x: 0, y: 0, width: maxWidth, height: 44)
            headerView.frame = headerFrame
        }
    }
}
