//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CoreServices
import Foundation
public import LibSignalClient
import MediaPlayer
import Photos
public import SignalServiceKit

public struct ApprovedAttachments {
    public let isViewOnce: Bool
    public let imageQuality: ImageQuality
    public let attachments: [PreviewableAttachment]

    private init(isViewOnce: Bool, imageQuality: ImageQuality, attachments: [PreviewableAttachment]) {
        owsPrecondition(!isViewOnce || attachments.count <= 1)
        self.isViewOnce = isViewOnce
        self.imageQuality = imageQuality
        self.attachments = attachments
    }

    public init(viewOnceAttachment: PreviewableAttachment, imageQuality: ImageQuality) {
        self.init(isViewOnce: true, imageQuality: imageQuality, attachments: [viewOnceAttachment])
    }

    public init(nonViewOnceAttachments: [PreviewableAttachment], imageQuality: ImageQuality) {
        self.init(isViewOnce: false, imageQuality: imageQuality, attachments: nonViewOnceAttachments)
    }
}

public protocol AttachmentApprovalViewControllerDelegate: AnyObject {

    func attachmentApproval(
        _ attachmentApproval: AttachmentApprovalViewController,
        didApproveAttachments approvedAttachments: ApprovedAttachments,
        messageBody: MessageBody?,
    )

    func attachmentApprovalDidCancel()

    func attachmentApproval(
        _ attachmentApproval: AttachmentApprovalViewController,
        didChangeMessageBody newMessageBody: MessageBody?,
    )
    func attachmentApproval(
        _ attachmentApproval: AttachmentApprovalViewController,
        didChangeViewOnceState isViewOnce: Bool,
    )

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachmentApprovalItem: AttachmentApprovalItem)

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController)
}

public protocol AttachmentApprovalViewControllerDataSource: AnyObject {

    var attachmentApprovalTextInputContextIdentifier: String? { get }

    var attachmentApprovalRecipientNames: [String] { get }

    func attachmentApprovalMentionableAcis(tx: DBReadTransaction) -> [Aci]

    func attachmentApprovalMentionCacheInvalidationKey() -> String
}

// MARK: -

public struct AttachmentApprovalViewControllerOptions: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let canAddMore = AttachmentApprovalViewControllerOptions(rawValue: 1 << 0)
    public static let hasCancel = AttachmentApprovalViewControllerOptions(rawValue: 1 << 1)
    public static let canToggleViewOnce = AttachmentApprovalViewControllerOptions(rawValue: 1 << 2)
    /// Overrides canToggleViewOnce and ensures that option is never enabled.
    public static let disallowViewOnce = AttachmentApprovalViewControllerOptions(rawValue: 1 << 3)
    public static let canChangeQualityLevel = AttachmentApprovalViewControllerOptions(rawValue: 1 << 4)
    public static let isNotFinalScreen = AttachmentApprovalViewControllerOptions(rawValue: 1 << 5)
}

// MARK: -

public final class AttachmentApprovalViewController: UIPageViewController, UIPageViewControllerDataSource,
    UIPageViewControllerDelegate, OWSNavigationChildController, GalleryRailViewDelegate, ApprovalRailCellViewDelegate,
    AttachmentPrepViewControllerDelegate, MediaCaptionToolbarDelegate, BodyRangesTextViewDelegate
{

    // MARK: - Properties

    private let receivedOptions: AttachmentApprovalViewControllerOptions

    private var options: AttachmentApprovalViewControllerOptions {
        var options = receivedOptions

        if
            attachmentApprovalItemCollection.attachmentApprovalItems.count == 1,
            let firstItem = attachmentApprovalItemCollection.attachmentApprovalItems.first,
            firstItem.attachment.isImage || firstItem.attachment.isVideo,
            !receivedOptions.contains(.disallowViewOnce)
        {
            options.insert(.canToggleViewOnce)
        }

        if
            ImageQualityLevel.maximumForCurrentAppContext() == .three,
            attachmentApprovalItemCollection.attachmentApprovalItems.contains(where: { $0.attachment.isImage })
        {
            options.insert(.canChangeQualityLevel)
        }

        return options
    }

    var isAddMoreVisible: Bool {
        return options.contains(.canAddMore) && !isViewOnceEnabled
    }

    var isViewOnceEnabled = false {
        didSet {
            approvalDelegate?.attachmentApproval(self, didChangeViewOnceState: isViewOnceEnabled)
        }
    }

    private var outputImageQuality: ImageQuality {
        didSet {
            updateBottomToolView(animated: false)
        }
    }

    public weak var approvalDelegate: AttachmentApprovalViewControllerDelegate?
    public weak var approvalDataSource: AttachmentApprovalViewControllerDataSource?

    public weak var stickerSheetDelegate: StickerPickerSheetDelegate?

    // MARK: - Initializers

    @available(*, unavailable, message: "use attachment: constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var observerToken: NSObjectProtocol?

    private var observingKeyboardNotifications = false
    private var keyboardHeight: CGFloat = 0 {
        didSet {
            guard let iOS15BottomToolviewVerticalPositionConstraint else { return }
            iOS15BottomToolviewVerticalPositionConstraint.constant = -max(view.safeAreaInsets.bottom, keyboardHeight)
        }
    }

    public let attachmentLimits: OutgoingAttachmentLimits

    public static func loadWithSneakyTransaction(
        attachmentApprovalItems: [AttachmentApprovalItem],
        attachmentLimits: OutgoingAttachmentLimits,
        options: AttachmentApprovalViewControllerOptions,
    ) -> Self {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return Self(
            attachmentApprovalItems: attachmentApprovalItems,
            defaultImageQuality: databaseStorage.read(block: ImageQuality.fetchValue(tx:)),
            attachmentLimits: attachmentLimits,
            options: options,
        )
    }

    private init(
        attachmentApprovalItems: [AttachmentApprovalItem],
        defaultImageQuality: ImageQuality,
        attachmentLimits: OutgoingAttachmentLimits,
        options: AttachmentApprovalViewControllerOptions,
    ) {
        assert(attachmentApprovalItems.count > 0)

        self.outputImageQuality = defaultImageQuality
        self.attachmentLimits = attachmentLimits
        self.receivedOptions = options

        let pageOptions: [UIPageViewController.OptionsKey: Any] = [.interPageSpacing: 20]
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: pageOptions)

        if Theme.forceDarkThemeForMedia {
            overrideUserInterfaceStyle = .dark
        }

        let isAddMoreVisibleBlock = { [weak self] in
            return self?.isAddMoreVisible ?? false
        }
        self.attachmentApprovalItemCollection = AttachmentApprovalItemCollection(
            attachmentApprovalItems: attachmentApprovalItems,
            isAddMoreVisible: isAddMoreVisibleBlock,
        )
        self.dataSource = self
        self.delegate = self

        // Bottom Bar
        self.galleryRailView.delegate = self
        self.bottomToolView.captionToolbarDelegate = self
        self.mediaCaptionToolbar.textViewDelegate = self

        observerToken = NotificationCenter.default.addObserver(forName: .OWSApplicationDidBecomeActive, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.updateContents(animated: false)
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    public class func wrappedInNavController(
        attachments: [PreviewableAttachment],
        initialMessageBody: MessageBody?,
        hasQuotedReplyDraft: Bool,
        attachmentLimits: OutgoingAttachmentLimits,
        approvalDelegate: AttachmentApprovalViewControllerDelegate,
        approvalDataSource: AttachmentApprovalViewControllerDataSource,
        stickerSheetDelegate: StickerPickerSheetDelegate?,
    ) -> OWSNavigationController {

        let attachmentApprovalItems = attachments.map { AttachmentApprovalItem(attachment: $0, canSave: false) }
        var options: AttachmentApprovalViewControllerOptions = []
        options.insert(.hasCancel)
        if hasQuotedReplyDraft {
            options.insert(.disallowViewOnce)
        }
        let vc = AttachmentApprovalViewController.loadWithSneakyTransaction(
            attachmentApprovalItems: attachmentApprovalItems,
            attachmentLimits: attachmentLimits,
            options: options,
        )
        // The data source needs to be set before the message body because it is needed to hydrate mentions.
        vc.approvalDataSource = approvalDataSource
        vc.setMessageBody(initialMessageBody, txProvider: DependenciesBridge.shared.db.readTxProvider)
        vc.approvalDelegate = approvalDelegate
        vc.stickerSheetDelegate = stickerSheetDelegate
        let navController = OWSNavigationController(rootViewController: vc)
        navController.setNavigationBarHidden(true, animated: false)
        return navController
    }

    // MARK: - Subviews

    var galleryRailView: GalleryRailView {
        return bottomToolView.galleryRailView
    }

    var mediaCaptionToolbar: MediaCaptionToolbar {
        return bottomToolView.mediaCaptionToolbar
    }

    private lazy var topBar = AttachmentApprovalTopBar(options: options)

    private let bottomToolView = AttachmentApprovalToolbar()

    // Manually adjust position of the bottom toolbar on iOS 15 because `keyboardLayoutGuide` is buggy.
    private var iOS15BottomToolviewVerticalPositionConstraint: NSLayoutConstraint?

    lazy var contentDimmerView: UIView = {
        let dimmerView = UIView()
        dimmerView.backgroundColor = .Signal.mediaBackground.withAlphaComponent(0.4)
        return dimmerView
    }()

    // MARK: - View Lifecycle

    override public var prefersStatusBarHidden: Bool {
        guard DependenciesBridge.shared.currentCallProvider.hasCurrentCall == false else { return false }
        return (UIDevice.current.isIPad || UIDevice.current.hasIPhoneXNotch) == false
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        Theme.forceDarkThemeForMedia ? .lightContent : .default
    }

    public var prefersNavigationBarHidden: Bool {
        true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        definesPresentationContext = true
        view.backgroundColor = .Signal.mediaBackground

        // avoid an unpleasant "bounce" which doesn't make sense in the context of a single item.
        pagerScrollView?.isScrollEnabled = attachmentApprovalItems.count > 1

        guard let firstItem = attachmentApprovalItems.first else {
            owsFailDebug("firstItem was unexpectedly nil")
            return
        }

        setCurrentItem(firstItem, direction: .forward, animated: false)

        // Top Bar
        topBar.cancelButton.addAction(
            UIAction { [weak self] _ in
                self?.cancelPressed()
            },
            for: .primaryActionTriggered,
        )
        topBar.backButton.addAction(
            UIAction { [weak self] _ in
                self?.navigateBackPressed()
            },
            for: .primaryActionTriggered,
        )
        topBar.install(in: view)

        // Bottom Bar
        bottomToolView.buttonProceed.addAction(
            UIAction { [weak self] _ in self?.didTapProceed() },
            for: .primaryActionTriggered,
        )
        bottomToolView.buttonPenTool.addAction(
            UIAction { [weak self] _ in self?.didTapPenTool() },
            for: .primaryActionTriggered,
        )
        bottomToolView.buttonCropTool.addAction(
            UIAction { [weak self] _ in self?.didTapCropTool() },
            for: .primaryActionTriggered,
        )
        bottomToolView.buttonMediaQuality.showsMenuAsPrimaryAction = true
        bottomToolView.buttonSaveMedia.addAction(
            UIAction { [weak self] _ in self?.didTapSave() },
            for: .primaryActionTriggered,
        )
        bottomToolView.buttonAddMedia.addAction(
            UIAction { [weak self] _ in self?.didTapAddMedia() },
            for: .primaryActionTriggered,
        )
        bottomToolView.buttonViewOnce.addAction(
            UIAction { [weak self] _ in self?.didToggleViewOnce() },
            for: .primaryActionTriggered,
        )

        view.addSubview(bottomToolView)
        bottomToolView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomToolView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // `bottomToolView` is pinned to the bottom of the screen.
        // However, it's content is re-positioned so that it clears the keyboard.
        if #unavailable(iOS 16) {
            let constraint = bottomToolView.contentLayoutGuide.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -view.safeAreaInsets.bottom,
            )
            constraint.isActive = true
            iOS15BottomToolviewVerticalPositionConstraint = constraint
        } else {
            NSLayoutConstraint.activate([
                bottomToolView.contentLayoutGuide.bottomAnchor.constraint(
                    equalTo: view.keyboardLayoutGuide.topAnchor,
                ),
            ])
        }

        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIViewController.attemptRotationToDeviceOrientation()

        topBar.update(withRecipientNames: approvalDataSource?.attachmentApprovalRecipientNames ?? [])

        updateContents(animated: false)

        if let currentPageViewController {
            updateContentLayoutMargins(for: currentPageViewController)
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        currentPageViewController?.prepareToMoveOffscreen()
        stopObservingKeyboardNotifications()
    }

    override public func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        if let iOS15BottomToolviewVerticalPositionConstraint {
            iOS15BottomToolviewVerticalPositionConstraint.constant = -max(view.safeAreaInsets.bottom, keyboardHeight)
        }
        if let currentPageViewController {
            updateContentLayoutMargins(for: currentPageViewController)
        }
    }

    // MARK: - UI Updates

    private func updateContentLayoutMargins(for viewController: AttachmentPrepViewController) {
        // The goal of all this layout logic is to lay out content in Review screen
        // the same way it will be laid out in Edit mode (drawing etc) so that activating editing tools
        // does not create any changes to media's size and position.
        // However AttachmentPrepViewController's view is always full screen and is managed by UIPageViewController,
        // which makes it not possible to constrain any of its subviews to the bottom toolbar.
        // The solution is to allow to set layout margins in AttachmentPrepViewController's view externally.

        var contentLayoutMargins: UIEdgeInsets = .zero
        // On devices with a screen notch at the top content is constrained to safe area inset so that status bar is visible.
        // On older devices content is pinned to the top of the screen and status bar is hidden to allow for more screen room.
        if prefersStatusBarHidden == false {
            contentLayoutMargins.top = view.safeAreaInsets.top
        }

        if let mediaEditingToolbarHeight = viewController.mediaEditingToolbarHeight {
            // For images there is an "edit" mode and it is necessary to keep image center the same
            // when switching to/from "edit" mode. Therefore image is laid out using bottom inset from "edit" mode screen.
            contentLayoutMargins.bottom = mediaEditingToolbarHeight
        } else {
            // bottomToolView contains UIStackView that doesn't always have a final frame at this point.
            bottomToolView.layoutIfNeeded()
            contentLayoutMargins.bottom = bottomToolView.opaqueAreaHeight

            // For videos there's thumbnail timeline bar embedded into the `bottomToolView`
            if let supplementaryView = viewController.toolbarSupplementaryView {
                contentLayoutMargins.bottom += supplementaryView.height
            }
        }
        contentLayoutMargins.bottom += view.safeAreaInsets.bottom

        viewController.contentLayoutMargins = contentLayoutMargins
    }

    private func updateContents(animated: Bool) {
        updateBottomToolView(animated: animated)
        updateMediaRail(animated: animated)
    }

    private func updateControlsVisibility(animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let alpha: CGFloat = shouldHideControls ? 0 : 1
        if animated {
            UIView.animate(
                withDuration: 0.15,
                animations: {
                    self.topBar.alpha = alpha
                    self.bottomToolView.alpha = alpha
                },
                completion: completion,
            )
        } else {
            topBar.alpha = alpha
            bottomToolView.alpha = alpha
            if let completion {
                completion(true)
            }
        }
    }

    private func updateSupplementaryToolbarView(using viewController: AttachmentPrepViewController, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.25) {
                self.bottomToolView.set(supplementaryView: viewController.toolbarSupplementaryView)
                self.bottomToolView.setNeedsLayout()
                self.bottomToolView.layoutIfNeeded()
            }
        } else {
            bottomToolView.set(supplementaryView: viewController.toolbarSupplementaryView)
        }
    }

    func updateMediaRail(animated: Bool = false) {
        guard isViewLoaded else { return }

        guard let currentItem else {
            owsFailDebug("currentItem was unexpectedly nil")
            return
        }

        let cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView = { [weak self] _ in
            let cell = ApprovalRailCellView()
            cell.approvalRailCellDelegate = self
            return cell
        }

        galleryRailView.configureCellViews(
            itemProvider: attachmentApprovalItemCollection,
            focusedItem: currentItem,
            cellViewBuilder: cellViewBuilder,
            animated: animated,
        )
    }

    private func updateBottomToolView(animated: Bool) {
        guard let currentPageViewController else { return }

        let isScreenNotFinal = options.contains(.isNotFinalScreen)
        let configuration = AttachmentApprovalToolbar.Configuration(
            isAddMoreVisible: isAddMoreVisible,
            isMediaStripVisible: attachmentApprovalItems.count > 1,
            isMediaHighQualityEnabled: outputImageQuality == .high,
            isViewOnceOn: isViewOnceEnabled,
            canToggleViewOnce: options.contains(.canToggleViewOnce),
            canChangeMediaQuality: options.contains(.canChangeQualityLevel),
            canSaveMedia: currentPageViewController.canSaveMedia,
            proceedButtonIcon: isScreenNotFinal ? .next : .send,
        )
        bottomToolView.update(
            currentAttachmentItem: currentPageViewController.attachmentApprovalItem,
            configuration: configuration,
            animated: animated,
        )
        // UIMenu needs to be re-created because it reflects current setting.
        bottomToolView.buttonMediaQuality.menu = mediaQualitySelectionMenu()
    }

    public var messageBodyForSending: MessageBody? {
        return mediaCaptionToolbar.messageBodyForSending
    }

    public func setMessageBody(_ messageBody: MessageBody?, txProvider: EditableMessageBodyTextStorage.ReadTxProvider) {
        mediaCaptionToolbar.setMessageBody(messageBody, txProvider: txProvider)
    }

    public var shouldHideControls: Bool {
        currentPageViewController?.shouldHideControls ?? false
    }

    // MARK: - View Helpers

    func remove(attachmentApprovalItem: AttachmentApprovalItem) {
        if attachmentApprovalItem.isIdenticalTo(currentItem) {
            if let nextItem = attachmentApprovalItemCollection.itemAfter(item: attachmentApprovalItem) {
                setCurrentItem(nextItem, direction: .forward, animated: true)
            } else if let prevItem = attachmentApprovalItemCollection.itemBefore(item: attachmentApprovalItem) {
                setCurrentItem(prevItem, direction: .reverse, animated: true)
            } else {
                owsFailBeta("removing last item shouldn't be possible because rail should not be visible")
                return
            }
        } else {
            owsFailBeta("Deleting item that is not current")
        }

        attachmentApprovalItemCollection.remove(item: attachmentApprovalItem)
        approvalDelegate?.attachmentApproval(self, didRemoveAttachment: attachmentApprovalItem)

        // If media rail needs to be hidden, do it immediately.
        if attachmentApprovalItems.count < 2 {
            updateMediaRail(animated: true)
        }
    }

    lazy var pagerScrollView: UIScrollView? = {
        // This is kind of a hack. Since we don't have first class access to the superview's `scrollView`
        // we traverse the view hierarchy until we find it.
        let pagerScrollView = view.subviews.first { $0 is UIScrollView } as? UIScrollView
        assert(pagerScrollView != nil)

        return pagerScrollView
    }()

    // MARK: - UIPageViewControllerDelegate

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController],
    ) {
        owsAssertDebug(pendingViewControllers.count == 1)

        // Pause video playback for current page
        currentPageViewController?.prepareToMoveOffscreen()

        // Update layout margins for view controllers to become visible.
        pendingViewControllers.forEach { viewController in
            guard let pendingPage = viewController as? AttachmentPrepViewController else {
                owsFailDebug("unexpected viewController: \(viewController)")
                return
            }
            updateContentLayoutMargins(for: pendingPage)
        }
    }

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted: Bool,
    ) {
        assert(previousViewControllers.count == 1)
        previousViewControllers.forEach { viewController in
            guard let previousPage = viewController as? AttachmentPrepViewController else {
                owsFailDebug("unexpected viewController: \(viewController)")
                return
            }

            if transitionCompleted {
                previousPage.zoomOut(animated: false)
            }
        }

        updateContents(animated: true)
        if let currentPageViewController {
            updateSupplementaryToolbarView(using: currentPageViewController, animated: true)
        }
    }

    // MARK: - UIPageViewControllerDataSource

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController,
    ) -> UIViewController? {
        guard let currentViewController = viewController as? AttachmentPrepViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        let currentItem = currentViewController.attachmentApprovalItem
        guard let previousItem = attachmentApprovalItem(before: currentItem) else {
            return nil
        }

        return buildPage(item: previousItem)
    }

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController,
    ) -> UIViewController? {
        guard let currentViewController = viewController as? AttachmentPrepViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        let currentItem = currentViewController.attachmentApprovalItem
        guard let nextItem = attachmentApprovalItem(after: currentItem) else {
            return nil
        }

        return buildPage(item: nextItem)
    }

    public var currentPageViewController: AttachmentPrepViewController? {
        return pageViewControllers.first
    }

    public var pageViewControllers: [AttachmentPrepViewController] {
        guard let viewControllers = super.viewControllers else {
            return []
        }
        return viewControllers.compactMap { $0 as? AttachmentPrepViewController }
    }

    var currentItem: AttachmentApprovalItem? {
        return currentPageViewController?.attachmentApprovalItem
    }

    private var cachedPages: [(key: AttachmentApprovalItem, value: AttachmentPrepViewController)] = []
    private func buildPage(item: AttachmentApprovalItem) -> AttachmentPrepViewController? {
        if let cachedPage = cachedPages.first(where: { $0.key.isIdenticalTo(item) }) {
            return cachedPage.value
        }

        guard
            let viewController = AttachmentPrepViewController.viewController(
                for: item,
                stickerSheetDelegate: stickerSheetDelegate,
            )
        else {
            owsFailDebug("Failed to create AttachmentPrepViewController.")
            return nil
        }

        viewController.prepDelegate = self
        cachedPages.append((item, viewController))

        return viewController
    }

    private func setCurrentItem(
        _ item: AttachmentApprovalItem,
        direction: UIPageViewController.NavigationDirection,
        animated: Bool,
    ) {
        guard let page = buildPage(item: item) else {
            owsFailDebug("unexpectedly unable to build new page")
            return
        }

        let previousPage = currentPageViewController

        // Pause video playback for current page
        currentPageViewController?.prepareToMoveOffscreen()

        page.loadViewIfNeeded()
        updateContentLayoutMargins(for: page)

        setViewControllers([page], direction: direction, animated: animated) { _ in
            previousPage?.zoomOut(animated: false)
        }

        // This does make animations smoother.
        DispatchQueue.main.async {
            self.updateContents(animated: animated)
            self.updateSupplementaryToolbarView(using: page, animated: animated)
        }
    }

    var attachmentApprovalItemCollection: AttachmentApprovalItemCollection!

    var attachmentApprovalItems: [AttachmentApprovalItem] {
        return attachmentApprovalItemCollection.attachmentApprovalItems
    }

    private func prepareAttachments() async throws -> [PreviewableAttachment] {
        var results = [PreviewableAttachment]()
        for attachmentApprovalItem in attachmentApprovalItems {
            results.append(
                try await self.prepareAttachment(attachmentApprovalItem: attachmentApprovalItem),
            )
        }
        return results
    }

    /// Returns a new SignalAttachment that reflects changes made in the editor.
    private func prepareAttachment(attachmentApprovalItem: AttachmentApprovalItem) async throws -> PreviewableAttachment {
        if let imageEditorModel = attachmentApprovalItem.imageEditorModel, imageEditorModel.isDirty {
            return try await self.prepareImageAttachment(
                attachmentApprovalItem: attachmentApprovalItem,
                imageEditorModel: imageEditorModel,
            )
        }
        if let videoEditorModel = attachmentApprovalItem.videoEditorModel, videoEditorModel.needsRender {
            return try await self.prepareVideoAttachment(
                attachmentApprovalItem: attachmentApprovalItem,
                videoEditorModel: videoEditorModel,
            )
        }
        // No editor applies. Use original, un-edited attachment.
        return attachmentApprovalItem.attachment
    }

    @concurrent
    private func prepareImageAttachment(
        attachmentApprovalItem: AttachmentApprovalItem,
        imageEditorModel: ImageEditorModel,
    ) async throws -> PreviewableAttachment {
        assert(imageEditorModel.isDirty)

        guard let dstImage = await imageEditorModel.renderOutput() else {
            throw OWSAssertionError("Could not render for output.")
        }

        let oldImage = imageEditorModel.srcImage
        let newImage = try NormalizedImage.forImage(
            dstImage,
            sourceFilename: oldImage.dataSource.sourceFilename,
            mayHaveTransparency: oldImage.mayHaveTransparency,
        )

        return PreviewableAttachment.imageAttachmentForNormalizedImage(newImage)
    }

    private func prepareVideoAttachment(
        attachmentApprovalItem: AttachmentApprovalItem,
        videoEditorModel: VideoEditorModel,
    ) async throws -> PreviewableAttachment {
        assert(videoEditorModel.needsRender)
        let fileUrl = try await videoEditorModel.render()
        let fileExtension = fileUrl.pathExtension
        guard let dataUTI = MimeTypeUtil.utiTypeForFileExtension(fileExtension) else {
            throw OWSAssertionError("Missing dataUTI.")
        }
        let dataSource = DataSourcePath(fileUrl: fileUrl, ownership: .owned)
        // Rewrite the filename's extension to reflect the output file format.
        var filename: String? = attachmentApprovalItem.attachment.rawValue.dataSource.sourceFilename?.filterFilename()
        if let sourceFilename = attachmentApprovalItem.attachment.rawValue.dataSource.sourceFilename?.filterFilename() {
            let sourceFilenameWithoutExtension = (sourceFilename as NSString).deletingPathExtension
            filename = (sourceFilenameWithoutExtension as NSString).appendingPathExtension(fileExtension) ?? sourceFilenameWithoutExtension
        }
        dataSource.sourceFilename = filename

        return try PreviewableAttachment.videoAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
    }

    func attachmentApprovalItem(before currentItem: AttachmentApprovalItem) -> AttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(where: { $0.isIdenticalTo(currentItem) }) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let index: Int = attachmentApprovalItems.index(before: currentIndex)
        guard let previousItem = attachmentApprovalItems[safe: index] else {
            // already at first item
            return nil
        }

        return previousItem
    }

    func attachmentApprovalItem(after currentItem: AttachmentApprovalItem) -> AttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(where: { $0.isIdenticalTo(currentItem) }) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let index: Int = attachmentApprovalItems.index(after: currentIndex)
        guard let nextItem = attachmentApprovalItems[safe: index] else {
            // already at last item
            return nil
        }

        return nextItem
    }

    // MARK: - ApprovalRailCellViewDelegate

    func approvalRailCellView(_ approvalRailCellView: ApprovalRailCellView, didRemoveItem attachmentApprovalItem: AttachmentApprovalItem) {
        remove(attachmentApprovalItem: attachmentApprovalItem)
    }

    func canRemoveApprovalRailCellView(_ approvalRailCellView: ApprovalRailCellView) -> Bool {
        return attachmentApprovalItems.count > 1
    }

    // MARK: - GalleryRailViewDelegate

    public func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem) {
        guard let targetItem = imageRailItem as? AttachmentApprovalItem else {
            owsFailDebug("unexpected imageRailItem: \(imageRailItem)")
            return
        }

        guard
            let currentItem,
            let currentIndex = attachmentApprovalItems.firstIndex(where: { $0.isIdenticalTo(currentItem) })
        else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return
        }

        guard let targetIndex = attachmentApprovalItems.firstIndex(where: { $0.isIdenticalTo(targetItem) }) else {
            owsFailDebug("targetIndex was unexpectedly nil")
            return
        }

        let direction: UIPageViewController.NavigationDirection = currentIndex < targetIndex ? .forward : .reverse
        setCurrentItem(targetItem, direction: direction, animated: true)
    }

    // MARK: - Event Handlers

    private func cancelPressed() {
        self.approvalDelegate?.attachmentApprovalDidCancel()
    }

    private func navigateBackPressed() {
        navigationController?.popViewController(animated: true)
    }

    private func didTapSave() {
        guard let currentItem else { return }
        Task { @MainActor in
            do {
                let saveableAsset: SaveableAsset = try SaveableAsset(attachmentApprovalItem: currentItem)

                let isGranted = await self.ows_askForMediaLibraryPermissions(for: .addOnly)
                guard isGranted else {
                    return
                }

                try await PHPhotoLibrary.shared().performChanges {
                    switch saveableAsset {
                    case .image(let image):
                        PHAssetCreationRequest.creationRequestForAsset(from: image)
                    case .imageUrl(let imageUrl):
                        PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: imageUrl)
                    case .videoUrl(let videoUrl):
                        PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: videoUrl)
                    }
                }

                let toastController = ToastController(text: OWSLocalizedString(
                    "ATTACHMENT_APPROVAL_MEDIA_DID_SAVE",
                    comment: "toast alert shown after user taps the 'save' button",
                ))
                toastController.presentToastView(
                    from: .bottom,
                    of: self.view,
                    inset: self.bottomToolView.height + 16,
                )
            } catch {
                Logger.error("Failed to save attachment to photo library: \(error)")
                OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                    "ATTACHMENT_APPROVAL_FAILED_TO_SAVE",
                    comment: "alert text when Signal was unable to save a copy of the attachment to the system photo library",
                ))
            }
        }
    }

    private func didTapAddMedia() {
        approvalDelegate?.attachmentApprovalDidTapAddMore(self)
    }

    private func didToggleViewOnce() {
        owsAssertDebug(options.contains(.canToggleViewOnce), "Cannot toggle `View Once`")

        isViewOnceEnabled = !isViewOnceEnabled
        SSKEnvironment.shared.preferencesRef.setWasViewOnceTooltipShown()

        updateBottomToolView(animated: true)
    }

    private func didTapProceed() {
        // Generate the attachments once, so that any changes we
        // make below are reflected afterwards.
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            title: CommonStrings.preparingModal,
            canCancel: false,
            asyncBlock: { modalVC in
                do {
                    let imageQuality = self.outputImageQuality
                    let attachments = try await self.prepareAttachments()
                    modalVC.dismiss {
                        let isViewOnce = self.options.contains(.canToggleViewOnce) && self.isViewOnceEnabled
                        let messageBody = self.mediaCaptionToolbar.messageBodyForSending
                        owsPrecondition(!isViewOnce || messageBody == nil)
                        self.approvalDelegate?.attachmentApproval(
                            self,
                            didApproveAttachments: {
                                if isViewOnce {
                                    // The `options` property and UI layer enforce this requirement.
                                    owsPrecondition(attachments.count == 1)
                                    return ApprovedAttachments(viewOnceAttachment: attachments.first!, imageQuality: imageQuality)
                                } else {
                                    return ApprovedAttachments(nonViewOnceAttachments: attachments, imageQuality: imageQuality)
                                }
                            }(),
                            messageBody: messageBody,
                        )
                    }
                } catch {
                    owsFailDebug("Error: \(error)")

                    modalVC.dismiss {
                        let actionSheet = ActionSheetController(
                            title: CommonStrings.errorAlertTitle,
                            message: (
                                (error as? SignalAttachmentError)?.localizedDescription
                                    ?? OWSLocalizedString("ATTACHMENT_APPROVAL_FAILED_TO_EXPORT", comment: "Error that outgoing attachments could not be exported."),
                            ),
                        )
                        if Theme.forceDarkThemeForMedia {
                            actionSheet.overrideUserInterfaceStyle = .dark
                        }
                        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton, style: .default))

                        self.present(actionSheet, animated: true)
                    }
                }
            },
        )
    }

    private func didTapPenTool() {
        currentPageViewController?.activatePenTool()
    }

    private func didTapCropTool() {
        currentPageViewController?.activateCropTool()
    }

    // MARK: - MediaCaptionToolbarDelegate {

    private func showContentDimmerView() {
        contentDimmerView.alpha = 0
        view.insertSubview(contentDimmerView, belowSubview: bottomToolView)
        contentDimmerView.autoPinEdgesToSuperviewEdges()
        UIView.animate(withDuration: 0.2) {
            self.contentDimmerView.alpha = 1
        }
        if contentDimmerView.gestureRecognizers?.isEmpty ?? true {
            contentDimmerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapContentDimmerView(gesture:))))
        }
    }

    private func hideContentDimmerView() {
        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.contentDimmerView.alpha = 0
            },
            completion: { _ in
                self.contentDimmerView.removeFromSuperview()
            },
        )
    }

    @objc
    func didTapContentDimmerView(gesture: UITapGestureRecognizer) {
        bottomToolView.finishTextEditing()
    }

    func mediaCaptionToolbarWillBeginEditing(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        startObservingKeyboardNotifications()
    }

    func mediaCaptionToolbarDidBeginEditing(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        showContentDimmerView()
    }

    func mediaCaptionToolbarDidEndEditing(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        hideContentDimmerView()
    }

    func mediaCaptionToolbarDidChangeText(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        approvalDelegate?.attachmentApproval(self, didChangeMessageBody: mediaCaptionToolbar.messageBodyForSending)
    }

    func mediaCaptionToolBarDidChangeHeight(_ mediaCaptionToolbar: MediaCaptionToolbar) { }

    private func startObservingKeyboardNotifications() {
        guard !observingKeyboardNotifications else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardDidHideNotification,
            object: nil,
        )
        observingKeyboardNotifications = true
    }

    private func stopObservingKeyboardNotifications() {
        guard observingKeyboardNotifications else { return }

        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
        observingKeyboardNotifications = false
    }

    @objc
    private func handleKeyboardNotification(_ notification: Notification) {
        guard
            let currentPageViewController,
            let userInfo = notification.userInfo,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        var keyboardHeight = endFrame.height

        switch notification.name {
        case UIResponder.keyboardDidHideNotification, UIResponder.keyboardWillHideNotification:
            keyboardHeight = 0

        default: break
        }

        guard self.keyboardHeight != keyboardHeight else { return }
        self.keyboardHeight = keyboardHeight

        if
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve)
        {
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                options: animationCurve.asAnimationOptions,
                animations: {
                    currentPageViewController.keyboardHeight = keyboardHeight
                },
            )
        } else {
            currentPageViewController.keyboardHeight = keyboardHeight
        }
    }

    // MARK: - Media Quality Selection UI

    private func mediaQualitySelectionMenu() -> UIMenu {
        let sdQualityItem = UIAction(title: ImageQuality.standard.localizedString) { [weak self] _ in
            // Setter updates UI.
            self?.outputImageQuality = .standard
        }
        sdQualityItem.subtitle = OWSLocalizedString(
            "ATTACHMENT_APPROVAL_MEDIA_QUALITY_STANDARD_OPTION_SUBTITLE",
            comment: "Subtitle for the 'standard' option for media quality.",
        )
        sdQualityItem.state = outputImageQuality == .standard ? .on : .off

        let hdQualityItem = UIAction(title: ImageQuality.high.localizedString) { [weak self] _ in
            // Setter updates UI.
            self?.outputImageQuality = .high
        }
        hdQualityItem.subtitle = OWSLocalizedString(
            "ATTACHMENT_APPROVAL_MEDIA_QUALITY_HIGH_OPTION_SUBTITLE",
            comment: "Subtitle for the 'high' option for media quality.",
        )
        hdQualityItem.state = outputImageQuality == .high ? .on : .off

        return UIMenu(
            title: OWSLocalizedString(
                "ATTACHMENT_APPROVAL_MEDIA_QUALITY_TITLE",
                comment: "Title for the attachment approval media quality sheet",
            ),
            children: [sdQualityItem, hdQualityItem],
        )
    }

    // MARK: - BodyRangesTextViewDelegate

    public func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) { }

    public func textViewDidEndTypingMention(_ textView: BodyRangesTextView) { }

    public func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        return view
    }

    public func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        return bottomToolView.mediaCaptionToolbar
    }

    public func textViewMentionPickerPossibleAcis(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [Aci] {
        return approvalDataSource?.attachmentApprovalMentionableAcis(tx: tx) ?? []
    }

    public func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        return .composingAttachment()
    }

    public func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
        return .composingAttachment
    }

    public func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        return approvalDataSource?.attachmentApprovalMentionCacheInvalidationKey() ?? UUID().uuidString
    }

    // MARK: - AttachmentPrepViewControllerDelegate

    func attachmentPrepViewControllerDidRequestUpdateControlsVisibility(
        _ viewController: AttachmentPrepViewController,
        completion: ((Bool) -> Void)? = nil,
    ) {
        updateControlsVisibility(animated: true, completion: completion)
    }
}

// MARK: -

extension AttachmentApprovalItem: GalleryRailItem {

    public func buildRailItemView() -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.image = getThumbnailImage()
        return imageView
    }

    public func isEqualToGalleryRailItem(_ other: (any GalleryRailItem)?) -> Bool {
        return self.isIdenticalTo(other as? Self)
    }
}

// MARK: -

extension AttachmentApprovalItemCollection: GalleryRailItemProvider {

    var railItems: [GalleryRailItem] { attachmentApprovalItems }
}

// MARK: -

private enum SaveableAsset {
    case image(_ image: UIImage)
    case imageUrl(_ url: URL)
    case videoUrl(_ url: URL)
}

// MARK: -

private extension SaveableAsset {
    @MainActor
    init(attachmentApprovalItem: AttachmentApprovalItem) throws {
        if let imageEditorModel = attachmentApprovalItem.imageEditorModel {
            try self.init(imageEditorModel: imageEditorModel)
        } else {
            try self.init(attachment: attachmentApprovalItem.attachment)
        }
    }

    @MainActor
    private init(imageEditorModel: ImageEditorModel) throws {
        guard let image = imageEditorModel.renderOutput() else {
            throw OWSAssertionError("failed to render image")
        }

        self = .image(image)
    }

    private init(attachment: PreviewableAttachment) throws {
        if attachment.isImage {
            let imageUrl = attachment.rawValue.dataSource.fileUrl
            self = .imageUrl(imageUrl)
        } else if attachment.isVideo {
            let videoUrl = attachment.rawValue.dataSource.fileUrl
            self = .videoUrl(videoUrl)
        } else {
            throw OWSAssertionError("unsaveable media")
        }
    }
}
