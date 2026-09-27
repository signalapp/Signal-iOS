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

public final class AttachmentApprovalViewController: OWSViewController, UIPageViewControllerDataSource,
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
            updateBottomToolView()
        }
    }

    public weak var approvalDelegate: AttachmentApprovalViewControllerDelegate?
    public weak var approvalDataSource: AttachmentApprovalViewControllerDataSource?

    public weak var stickerSheetDelegate: StickerPickerSheetDelegate?

    // MARK: - Initializers

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var observerToken: NSObjectProtocol?

    private var observingKeyboardNotifications = false

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

        super.init()

        if Theme.forceDarkThemeForMedia {
            overrideUserInterfaceStyle = .dark
        }

        let isAddMoreVisibleBlock = { [weak self] in
            return self?.isAddMoreVisible ?? false
        }
        attachmentApprovalItemCollection = AttachmentApprovalItemCollection(
            attachmentApprovalItems: attachmentApprovalItems,
            isAddMoreVisible: isAddMoreVisibleBlock,
        )

        observerToken = NotificationCenter.default.addObserver(
            forName: .OWSApplicationDidBecomeActive,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
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

    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: [.interPageSpacing: 20],
    )

    var galleryRailView: GalleryRailView {
        return bottomToolView.galleryRailView
    }

    var mediaCaptionToolbar: MediaCaptionToolbar {
        return bottomToolView.mediaCaptionToolbar
    }

    private lazy var topBar = AttachmentApprovalTopBar(options: options)

    private let bottomToolView = AttachmentApprovalToolbar()

    lazy var contentDimmerView: UIView = {
        let dimmerView = UIView()
        dimmerView.backgroundColor = .ows_blackAlpha40
        return dimmerView
    }()

    // MARK: - View Lifecycle

    override public var prefersStatusBarHidden: Bool {
        guard DependenciesBridge.shared.currentCallProvider.hasCurrentCall == false else {
            return super.prefersStatusBarHidden
        }
        guard
            let appWindow = CurrentAppContext().mainWindow,
            appWindow.shouldHideStatusBarForFullScreenPresentation
        else {
            return super.prefersStatusBarHidden
        }
        return true
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

        // UIPageViewController is added as a child because I needed to set
        // additional safe area insets (heights of top and bottom controls) on pages only,
        // leaving parent view unaffected and keeping toolbars with the default safe area insets.
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Do not allow scrolling when there's just one item.
        if let pagingScrollView = pageViewController.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            pagingScrollView.isScrollEnabled = attachmentApprovalItems.count > 1
        }

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
        galleryRailView.delegate = self
        bottomToolView.captionToolbarDelegate = self
        mediaCaptionToolbar.textViewDelegate = self
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
        bottomToolView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomToolView)
        NSLayoutConstraint.activate([
            bottomToolView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIViewController.attemptRotationToDeviceOrientation()

        topBar.update(withRecipientNames: approvalDataSource?.attachmentApprovalRecipientNames ?? [])

        updateContents(animated: false)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        currentPageViewController?.prepareToMoveOffscreen()
        stopObservingKeyboardNotifications()
    }

    override public func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()

        updatePageViewContollerSafeAreaInsets()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updatePageViewContollerSafeAreaInsets()
    }

    // MARK: - UI Updates

    private func updatePageViewContollerSafeAreaInsets() {
        // Both heights need to exclude current view's safe area insets because
        // pageViewController would already have those.

        let topBarContentHeight = max(0, topBar.frame.maxY - view.safeAreaInsets.top)
        pageViewController.additionalSafeAreaInsets.top = topBarContentHeight

        let bottomToolbarContentHeight = max(0, bottomToolView.currentHeight - view.safeAreaInsets.bottom)
        pageViewController.additionalSafeAreaInsets.bottom = bottomToolbarContentHeight
    }

    private func updateContents(animated: Bool) {
        guard animated else {
            updateBottomToolView()
            updateMediaRail()
            return
        }
        let animator = AttachmentApprovalToolbar.defaultAnimator()
        updateBottomToolView(animator: animator)
        animator.addAnimations {
            self.updateMediaRail(animated: false)
        }
        animator.startAnimation()
    }

    private func updateControlsVisibility(animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let alpha: CGFloat = shouldHideControls ? 0 : 1

        guard animated else {
            topBar.alpha = alpha
            bottomToolView.alpha = alpha
            if let completion {
                completion(true)
            }
            return
        }

        let animator = AttachmentApprovalToolbar.defaultAnimator()
        animator.addAnimations {
            self.topBar.alpha = alpha
            self.bottomToolView.alpha = alpha
        }
        if let completion {
            animator.addCompletion { _ in
                completion(true)
            }
        }
        animator.startAnimation()
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
        guard animated else {
            updateBottomToolView()
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.15, springDamping: 1, springResponse: 0.15)
        updateBottomToolView(animator: animator)
        animator.startAnimation()
    }

    private func updateBottomToolView(animator: UIViewPropertyAnimator? = nil) {
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
            using: currentPageViewController.attachmentApprovalItem,
            configuration: configuration,
            supplementaryToolbarView: currentPageViewController.toolbarSupplementaryView,
            animator: animator,
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

    // MARK: - UIPageViewControllerDelegate

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController],
    ) {
        owsAssertDebug(pendingViewControllers.count == 1)

        // Pause video playback for current page
        currentPageViewController?.prepareToMoveOffscreen()
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
        return pageViewController.viewControllers?.first as? AttachmentPrepViewController
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

        // Pause video playback for current page.
        previousPage?.prepareToMoveOffscreen()

        page.loadViewIfNeeded()

        pageViewController.setViewControllers(
            [page],
            direction: direction,
            animated: animated,
        ) { _ in
            previousPage?.zoomOut(animated: false)
        }

        // This does make animations smoother.
        DispatchQueue.main.async {
            self.updateContents(animated: animated)
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
        let isDirty = await imageEditorModel.isDirty
        assert(isDirty)

        guard let dstImage = await imageEditorModel.renderOutput() else {
            throw OWSAssertionError("Could not render for output.")
        }

        let oldImage = await imageEditorModel.srcImage
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
        guard observingKeyboardNotifications == false else { return }

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
            let userInfo = notification.userInfo,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        let keyboardFrame = view.convert(endFrame, from: nil)
        let viewFrame = view.bounds

        let keyboardHeight: CGFloat
        if keyboardFrame.minY >= viewFrame.maxY {
            // Offscreen
            keyboardHeight = 0
        } else if keyboardFrame.maxY < viewFrame.maxY {
            // Floating
            keyboardHeight = 0
        } else {
            keyboardHeight = keyboardFrame.height
        }

        if
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve)
        {
            let animator = UIViewPropertyAnimator(
                duration: animationDuration,
                curve: animationCurve,
            )
            // This would position caption input field above the on-screen keyboard
            // and hide controls other than caption input field.
            bottomToolView.setKeyboardHeight(keyboardHeight, using: animator)
            // This would shift the scroll view up and apply scale down animation when keyboard is up.
            animator.addAnimations {
                self.updateScrollViewTransform(keyboardHeight: keyboardHeight)
                self.view.layoutIfNeeded()
            }
            animator.startAnimation()
        } else {
            bottomToolView.setKeyboardHeight(keyboardHeight)
            updateScrollViewTransform(keyboardHeight: keyboardHeight)
        }
    }

    private func updateScrollViewTransform(keyboardHeight: CGFloat) {
        currentPageViewController?.updateScrollViewTransform(keyboardHeight: keyboardHeight)
    }

    // MARK: - Media Quality Selection UI

    private func mediaQualitySelectionMenu() -> UIMenu {
        let sdQualityItem = UIAction(
            title: ImageQuality.standard.localizedString,
            subtitle: OWSLocalizedString(
                "ATTACHMENT_APPROVAL_MEDIA_QUALITY_STANDARD_OPTION_SUBTITLE",
                comment: "Subtitle for the 'standard' option for media quality.",
            ),
        ) { [weak self] _ in
            // Setter updates UI.
            self?.outputImageQuality = .standard
        }
        sdQualityItem.state = outputImageQuality == .standard ? .on : .off

        let hdQualityItem = UIAction(
            title: ImageQuality.high.localizedString,
            subtitle: OWSLocalizedString(
                "ATTACHMENT_APPROVAL_MEDIA_QUALITY_HIGH_OPTION_SUBTITLE",
                comment: "Subtitle for the 'high' option for media quality.",
            ),
        ) { [weak self] _ in
            // Setter updates UI.
            self?.outputImageQuality = .high
        }
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

extension AttachmentApprovalItem: @MainActor GalleryRailItem {

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

extension AttachmentApprovalItemCollection: @MainActor GalleryRailItemProvider {

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
