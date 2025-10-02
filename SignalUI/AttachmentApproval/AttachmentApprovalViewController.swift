//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AVFoundation
import MediaPlayer
import Photos
import CoreServices
public import SignalServiceKit

public protocol AttachmentApprovalViewControllerDelegate: AnyObject {

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?)

    func attachmentApprovalDidCancel()

    func attachmentApproval(
        _ attachmentApproval: AttachmentApprovalViewController,
        didChangeMessageBody newMessageBody: MessageBody?
    )
    func attachmentApproval(
        _ attachmentApproval: AttachmentApprovalViewController,
        didChangeViewOnceState isViewOnce: Bool
    )

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment)

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController)
}

public protocol AttachmentApprovalViewControllerDataSource: AnyObject {

    var attachmentApprovalTextInputContextIdentifier: String? { get }

    var attachmentApprovalRecipientNames: [String] { get }

    func attachmentApprovalMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress]

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

public class AttachmentApprovalViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, OWSNavigationChildController {

    // MARK: - Properties

    private let receivedOptions: AttachmentApprovalViewControllerOptions

    private var options: AttachmentApprovalViewControllerOptions {
        var options = receivedOptions

        if
            attachmentApprovalItemCollection.attachmentApprovalItems.count == 1,
            let firstItem = attachmentApprovalItemCollection.attachmentApprovalItems.first,
            firstItem.attachment.isValidImage || firstItem.attachment.isValidVideo,
            !receivedOptions.contains(.disallowViewOnce)
        {
            options.insert(.canToggleViewOnce)
        }

        if
            ImageQualityLevel.maximumForCurrentAppContext == .high,
            attachmentApprovalItemCollection.attachmentApprovalItems.contains(where: { $0.attachment.isValidImage }) {
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

    lazy var outputQualityLevel: ImageQualityLevel = SSKEnvironment.shared.databaseStorageRef.read { .resolvedQuality(tx: $0) }

    public weak var approvalDelegate: AttachmentApprovalViewControllerDelegate?
    public weak var approvalDataSource: AttachmentApprovalViewControllerDataSource?

    public weak var stickerSheetDelegate: StickerPickerSheetDelegate?

    // MARK: - Initializers

    @available(*, unavailable, message: "use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let kSpacingBetweenItems: CGFloat = 20

    private var observerToken: NSObjectProtocol?

    private var observingKeyboardNotifications = false
    private var keyboardHeight: CGFloat = 0 {
        didSet {
            guard let iOS15BottomToolviewVerticalPositionConstraint else { return }
            iOS15BottomToolviewVerticalPositionConstraint.constant = -max(view.safeAreaInsets.bottom, keyboardHeight)
        }
    }

    public init(options: AttachmentApprovalViewControllerOptions, attachmentApprovalItems: [AttachmentApprovalItem]) {
        assert(attachmentApprovalItems.count > 0)

        self.receivedOptions = options

        let pageOptions: [UIPageViewController.OptionsKey: Any] = [.interPageSpacing: kSpacingBetweenItems]
        super.init(transitionStyle: .scroll,
                   navigationOrientation: .horizontal,
                   options: pageOptions)

        let isAddMoreVisibleBlock = { [weak self] in
            return self?.isAddMoreVisible ?? false
        }
        self.attachmentApprovalItemCollection = AttachmentApprovalItemCollection(attachmentApprovalItems: attachmentApprovalItems, isAddMoreVisible: isAddMoreVisibleBlock)
        self.dataSource = self
        self.delegate = self

        // Bottom Bar
        self.galleryRailView.delegate = self
        self.bottomToolView.attachmentTextToolbarDelegate = self
        self.attachmentTextToolbar.mentionTextViewDelegate = self

        // This fixes an issue with keyboard flashing white while being dismissed.
        overrideUserInterfaceStyle = .dark

        observerToken = NotificationCenter.default.addObserver(forName: .OWSApplicationDidBecomeActive, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.updateContents(animated: false)
        }
    }

    deinit {
        if let observerToken = observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    public class func wrappedInNavController(
        attachments: [SignalAttachment],
        initialMessageBody: MessageBody?,
        hasQuotedReplyDraft: Bool,
        approvalDelegate: AttachmentApprovalViewControllerDelegate,
        approvalDataSource: AttachmentApprovalViewControllerDataSource,
        stickerSheetDelegate: StickerPickerSheetDelegate?
    ) -> OWSNavigationController {

        let attachmentApprovalItems = attachments.map { AttachmentApprovalItem(attachment: $0, canSave: false) }
        var options: AttachmentApprovalViewControllerOptions = []
        options.insert(.hasCancel)
        if hasQuotedReplyDraft {
            options.insert(.disallowViewOnce)
        }
        let vc = AttachmentApprovalViewController(options: options, attachmentApprovalItems: attachmentApprovalItems)
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

    var attachmentTextToolbar: AttachmentTextToolbar {
        return bottomToolView.attachmentTextToolbar
    }

    private lazy var topBar = AttachmentApprovalTopBar(options: options)

    private let bottomToolView = AttachmentApprovalToolbar()

    // Manually adjust position of the bottom toolbar on iOS 15 because `keyboardLayoutGuide` is buggy.
    private var iOS15BottomToolviewVerticalPositionConstraint: NSLayoutConstraint?

    lazy var contentDimmerView: UIView = {
        let dimmerView = UIView()
        dimmerView.backgroundColor = .ows_blackAlpha40
        return dimmerView
    }()

    // MARK: - View Lifecycle

    public override var prefersStatusBarHidden: Bool {
        !UIDevice.current.hasIPhoneXNotch && !UIDevice.current.isIPad && !DependenciesBridge.shared.currentCallProvider.hasCurrentCall
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    public var prefersNavigationBarHidden: Bool {
        return true
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        // avoid an unpleasant "bounce" which doesn't make sense in the context of a single item.
        pagerScrollView?.isScrollEnabled = attachmentApprovalItems.count > 1

        // Navigation
        navigationItem.title = nil

        guard let firstItem = attachmentApprovalItems.first else {
            owsFailDebug("firstItem was unexpectedly nil")
            return
        }

        setCurrentItem(firstItem, direction: .forward, animated: false)

        // Top Bar
        topBar.cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        topBar.backButton.addTarget(self, action: #selector(navigateBackPressed), for: .touchUpInside)

        let topBarSize = topBar.systemLayoutSizeFitting(view.bounds.size, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        topBar.frame = CGRect(x: 0, y: view.layoutMargins.top, width: view.width, height: topBarSize.height)
        UIView.performWithoutAnimation {
            topBar.setNeedsLayout()
            topBar.layoutIfNeeded()
        }
        topBar.install(in: view)

        bottomToolView.buttonAddMedia.addTarget(self, action: #selector(didTapAddMedia), for: .touchUpInside)
        bottomToolView.buttonViewOnce.addTarget(self, action: #selector(didToggleViewOnce), for: .touchUpInside)
        bottomToolView.buttonSend.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)
        bottomToolView.buttonMediaQuality.addTarget(self, action: #selector(didTapMediaQuality), for: .touchUpInside)
        bottomToolView.buttonSaveMedia.addTarget(self, action: #selector(didTapSave), for: .touchUpInside)
        bottomToolView.buttonPenTool.addTarget(self, action: #selector(didTapPenTool), for: .touchUpInside)
        bottomToolView.buttonCropTool.addTarget(self, action: #selector(didTapCropTool), for: .touchUpInside)

        let bottomToolViewWidth = view.bounds.width
        let bottomToolViewHeight = bottomToolView.systemLayoutSizeFitting(view.bounds.size, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        bottomToolView.frame = CGRect(x: 0, y: view.bounds.maxY - bottomToolViewHeight, width: bottomToolViewWidth, height: bottomToolViewHeight)
        UIView.performWithoutAnimation {
            bottomToolView.setNeedsLayout()
            bottomToolView.layoutIfNeeded()
        }
        view.addSubview(bottomToolView)
        bottomToolView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomToolView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        if #unavailable(iOS 16) {
            let constraint = bottomToolView.contentLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -view.safeAreaInsets.bottom)
            constraint.isActive = true
            iOS15BottomToolviewVerticalPositionConstraint = constraint
        } else {
            NSLayoutConstraint.activate([
                bottomToolView.contentLayoutGuide.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
            ])
        }

        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        Logger.debug("")
        super.viewWillAppear(animated)

        UIViewController.attemptRotationToDeviceOrientation()

        topBar.update(withRecipientNames: approvalDataSource?.attachmentApprovalRecipientNames ?? [])

        updateContents(animated: false)

        if let currentPageViewController {
            updateContentLayoutMargins(for: currentPageViewController)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        Logger.debug("")
        super.viewDidAppear(animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        Logger.debug("")
        super.viewWillDisappear(animated)

        currentPageViewController?.prepareToMoveOffscreen()
        stopObservingKeyboardNotifications()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        if let iOS15BottomToolviewVerticalPositionConstraint {
            iOS15BottomToolviewVerticalPositionConstraint.constant = -max(view.safeAreaInsets.bottom, keyboardHeight)
        }
        if let currentPageViewController {
            updateContentLayoutMargins(for: currentPageViewController)
        }
    }

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
        if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
            contentLayoutMargins.top = view.safeAreaInsets.top
        }

        if let mediaEditingToolbarHeight = viewController.mediaEditingToolbarHeight {
            // For images there is an "edit" mode and it is necessary to keep image center the same
            // when switching to/from "edit" mode. Therefore image is laid out usign bottom inset from "edit" mode screen.
            contentLayoutMargins.bottom = mediaEditingToolbarHeight
        } else {
            // bottomToolView contains UIStackView that doesn't always have a final frame at this point.
            bottomToolView.layoutIfNeeded()
            contentLayoutMargins.bottom = bottomToolView.opaqueAreaHeight

            // For videos there's thumbnail timelinebar embedded into the `bottomToolView`
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

    // MARK: - Input Accessory

    private func updateControlsVisibility(animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let alpha: CGFloat = shouldHideControls ? 0 : 1
        if animated {
            UIView.animate(withDuration: 0.15,
                           animations: {
                self.topBar.alpha = alpha
                self.bottomToolView.alpha = alpha
            }, completion: completion)
        } else {
            topBar.alpha = alpha
            bottomToolView.alpha = alpha
            if let completion = completion {
                completion(true)
            }
        }
    }

    private func updateBottomToolView(animated: Bool) {
        guard let currentPageViewController = currentPageViewController else { return }

        let isScreenNotFinal = options.contains(.isNotFinalScreen)
        let configuration = AttachmentApprovalToolbar.Configuration(
            isAddMoreVisible: isAddMoreVisible,
            isMediaStripVisible: attachmentApprovalItems.count > 1,
            isMediaHighQualityEnabled: outputQualityLevel == .high,
            isViewOnceOn: isViewOnceEnabled,
            canToggleViewOnce: options.contains(.canToggleViewOnce),
            canChangeMediaQuality: options.contains(.canChangeQualityLevel),
            canSaveMedia: currentPageViewController.canSaveMedia,
            doneButtonIcon: isScreenNotFinal ? .next : .send
        )
        bottomToolView.update(
            currentAttachmentItem: currentPageViewController.attachmentApprovalItem,
            configuration: configuration,
            animated: animated
        )
    }

    public var messageBodyForSending: MessageBody? {
        return attachmentTextToolbar.messageBodyForSending
    }

    public func setMessageBody(_ messageBody: MessageBody?, txProvider: EditableMessageBodyTextStorage.ReadTxProvider) {
        attachmentTextToolbar.setMessageBody(messageBody, txProvider: txProvider)
    }

    // MARK: - Control Visibility

    public var shouldHideControls: Bool {
        currentPageViewController?.shouldHideControls ?? false
    }

    // MARK: - View Helpers

    func remove(attachmentApprovalItem: AttachmentApprovalItem) {
        if attachmentApprovalItem == currentItem {
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
        approvalDelegate?.attachmentApproval(self, didRemoveAttachment: attachmentApprovalItem.attachment)

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

    public func pageViewController(_ pageViewController: UIPageViewController,
                                   willTransitionTo pendingViewControllers: [UIViewController]) {
        Logger.debug("")

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

    public func pageViewController(_ pageViewController: UIPageViewController,
                                   didFinishAnimating finished: Bool,
                                   previousViewControllers: [UIViewController],
                                   transitionCompleted: Bool) {
        Logger.debug("")

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
        if let currentPageViewController = currentPageViewController {
            updateSupplementaryToolbarView(using: currentPageViewController, animated: true)
        }
    }

    // MARK: - UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController,
                                   viewControllerBefore viewController: UIViewController) -> UIViewController? {
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

    public func pageViewController(_ pageViewController: UIPageViewController,
                                   viewControllerAfter viewController: UIViewController) -> UIViewController? {
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

    private var cachedPages: [AttachmentApprovalItem: AttachmentPrepViewController] = [:]
    private func buildPage(item: AttachmentApprovalItem) -> AttachmentPrepViewController? {

        if let cachedPage = cachedPages[item] {
            Logger.debug("cache hit.")
            return cachedPage
        }

        Logger.debug("cache miss.")
        guard let viewController = AttachmentPrepViewController.viewController(
            for: item,
            stickerSheetDelegate: stickerSheetDelegate
        ) else {
            owsFailDebug("Failed to create AttachmentPrepViewController.")
            return nil
        }

        viewController.prepDelegate = self
        cachedPages[item] = viewController

        return viewController
    }

    private func setCurrentItem(_ item: AttachmentApprovalItem,
                                direction: UIPageViewController.NavigationDirection,
                                animated: Bool) {

        guard let page = buildPage(item: item) else {
            owsFailDebug("unexpectedly unable to build new page")
            return
        }

        let previousPage = currentPageViewController

        // Pause video playback for current page
        currentPageViewController?.prepareToMoveOffscreen()

        page.loadViewIfNeeded()
        updateContentLayoutMargins(for: page)

        Logger.debug("currentItem for attachment: \(item.attachment.debugDescription)")
        setViewControllers([page], direction: direction, animated: animated) { _ in
            previousPage?.zoomOut(animated: false)
        }

        // This does make animations smoother.
        DispatchQueue.main.async {
            self.updateContents(animated: animated)
            self.updateSupplementaryToolbarView(using: page, animated: animated)
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

        let cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView = { [weak self] railItem in
            switch railItem {
            case is AddMoreRailItem:
                return AddMediaRailCellView()
            case is AttachmentApprovalItem:
                let cell = ApprovalRailCellView()
                cell.approvalRailCellDelegate = self
                return cell
            default:
                owsFailDebug("unexpected rail item type: \(railItem)")
                return GalleryRailCellView()
            }
        }

        galleryRailView.configureCellViews(itemProvider: attachmentApprovalItemCollection,
                                           focusedItem: currentItem,
                                           cellViewBuilder: cellViewBuilder,
                                           animated: animated)
    }

    var attachmentApprovalItemCollection: AttachmentApprovalItemCollection!

    var attachmentApprovalItems: [AttachmentApprovalItem] {
        return attachmentApprovalItemCollection.attachmentApprovalItems
    }

    func outputAttachmentsPromise() -> Promise<[SignalAttachment]> {
        var promises = [Promise<SignalAttachment>]()
        for attachmentApprovalItem in attachmentApprovalItems {
            let outputQualityLevel = self.outputQualityLevel
            promises.append(outputAttachmentPromise(for: attachmentApprovalItem).map(on: DispatchQueue.global()) { attachment in
                attachment.preparedForOutput(qualityLevel: outputQualityLevel)
            })
        }
        return Promise.when(fulfilled: promises)
    }

    // For any attachments edited with an editor, returns a
    // new SignalAttachment that reflects those changes.  Otherwise,
    // returns the original attachment.
    //
    // If any errors occurs in the export process, we fail over to
    // sending the original attachment.  This seems better than trying
    // to involve the user in resolving the issue.
    func outputAttachmentPromise(for attachmentApprovalItem: AttachmentApprovalItem) -> Promise<SignalAttachment> {
        if let imageEditorModel = attachmentApprovalItem.imageEditorModel, imageEditorModel.isDirty() {
            return editedAttachmentPromise(imageEditorModel: imageEditorModel,
                                           attachmentApprovalItem: attachmentApprovalItem)
        }
        if let videoEditorModel = attachmentApprovalItem.videoEditorModel, videoEditorModel.needsRender {
            return .wrapAsync {
                try await self.renderAttachment(videoEditorModel: videoEditorModel, attachmentApprovalItem: attachmentApprovalItem)
            }
        }
        // No editor applies. Use original, un-edited attachment.
        return Promise.value(attachmentApprovalItem.attachment)
    }

    // For any attachments edited with the image editor, returns a
    // new SignalAttachment that reflects those changes.
    //
    // If any errors occurs in the export process, we fail over to
    // sending the original attachment.  This seems better than trying
    // to involve the user in resolving the issue.
    func editedAttachmentPromise(imageEditorModel: ImageEditorModel,
                                 attachmentApprovalItem: AttachmentApprovalItem) -> Promise<SignalAttachment> {
        assert(imageEditorModel.isDirty())
        return DispatchQueue.main.async(.promise) { () -> UIImage in
            guard let dstImage = imageEditorModel.renderOutput() else {
                throw OWSAssertionError("Could not render for output.")
            }
            return dstImage
        }.map(on: DispatchQueue.global()) { (dstImage: UIImage) -> SignalAttachment in
            var dataType = UTType.image
            guard let dstData: Data = {
                let isLossy: Bool = attachmentApprovalItem.attachment.mimeType.caseInsensitiveCompare(MimeType.imageJpeg.rawValue) == .orderedSame
                if isLossy {
                    dataType = .jpeg
                    return dstImage.jpegData(compressionQuality: 0.9)
                } else {
                    dataType = .png
                    return dstImage.pngData()
                }
                }() else {
                    owsFailDebug("Could not export for output.")
                    return attachmentApprovalItem.attachment
            }
            guard let dataSource = DataSourceValue(dstData, utiType: dataType.identifier) else {
                owsFailDebug("Could not prepare data source for output.")
                return attachmentApprovalItem.attachment
            }

            // Rewrite the filename's extension to reflect the output file format.
            var filename: String? = attachmentApprovalItem.attachment.sourceFilename
            if let sourceFilename = attachmentApprovalItem.attachment.sourceFilename {
                if let fileExtension: String = MimeTypeUtil.fileExtensionForUtiType(dataType.identifier) {
                    filename = (sourceFilename as NSString).deletingPathExtension.appendingFileExtension(fileExtension)
                }
            }
            dataSource.sourceFilename = filename

            let dstAttachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataType.identifier)
            if let attachmentError = dstAttachment.error {
                owsFailDebug("Could not prepare attachment for output: \(attachmentError).")
                return attachmentApprovalItem.attachment
            }
            return dstAttachment
        }
    }

    // For any attachments edited with the video editor, returns a
    // new SignalAttachment that reflects those changes.
    //
    // If any errors occurs in the export process, we fail over to
    // sending the original attachment.  This seems better than trying
    // to involve the user in resolving the issue.
    func renderAttachment(videoEditorModel: VideoEditorModel, attachmentApprovalItem: AttachmentApprovalItem) async throws -> SignalAttachment {
        assert(videoEditorModel.needsRender)
        let result = try await videoEditorModel.ensureCurrentRender().render()
        let filePath = try result.consumeResultPath()
        guard let fileExtension = filePath.fileExtension else {
            throw OWSAssertionError("Missing fileExtension.")
        }
        guard let dataUTI = MimeTypeUtil.utiTypeForFileExtension(fileExtension) else {
            throw OWSAssertionError("Missing dataUTI.")
        }
        let dataSource = try DataSourcePath(filePath: filePath, shouldDeleteOnDeallocation: true)
        // Rewrite the filename's extension to reflect the output file format.
        var filename: String? = attachmentApprovalItem.attachment.sourceFilename
        if let sourceFilename = attachmentApprovalItem.attachment.sourceFilename {
            filename = (sourceFilename as NSString).deletingPathExtension.appendingFileExtension(fileExtension)
        }
        dataSource.sourceFilename = filename

        let dstAttachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataUTI)
        if let attachmentError = dstAttachment.error {
            throw OWSAssertionError("Could not prepare attachment for output: \(attachmentError).")
        }
        dstAttachment.isViewOnceAttachment = attachmentApprovalItem.attachment.isViewOnceAttachment
        return dstAttachment
    }

    func attachmentApprovalItem(before currentItem: AttachmentApprovalItem) -> AttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(of: currentItem) else {
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
        guard let currentIndex = attachmentApprovalItems.firstIndex(of: currentItem) else {
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
}

// MARK: - Event Handlers

extension AttachmentApprovalViewController {

    @objc
    private func cancelPressed() {
        self.approvalDelegate?.attachmentApprovalDidCancel()
    }

    @objc
    private func navigateBackPressed() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func didTapSave() {
        guard let currentItem = currentItem else { return }
        Task { @MainActor in
            do {
                let saveableAsset: SaveableAsset = try SaveableAsset(attachmentApprovalItem: currentItem)

                let isGranted = await self.ows_askForMediaLibraryPermissions(for: .addOnly)
                guard isGranted else {
                    return
                }

                try await PHPhotoLibrary.shared().performChanges{
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
                    comment: "toast alert shown after user taps the 'save' button"
                ))
                toastController.presentToastView(
                    from: .bottom,
                    of: self.view,
                    inset: self.bottomToolView.height + 16
                )
            } catch {
                Logger.error("Failed to save attachment to photo library: \(error)")
                OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                    "ATTACHMENT_APPROVAL_FAILED_TO_SAVE",
                    comment: "alert text when Signal was unable to save a copy of the attachment to the system photo library"
                ))
            }
        }
    }

    @objc
    private func didTapAddMedia() {
        approvalDelegate?.attachmentApprovalDidTapAddMore(self)
    }

    @objc
    private func didToggleViewOnce() {
        owsAssertDebug(options.contains(.canToggleViewOnce), "Cannot toggle `View Once`")

        isViewOnceEnabled = !isViewOnceEnabled
        SSKEnvironment.shared.preferencesRef.setWasViewOnceTooltipShown()

        updateBottomToolView(animated: true)
    }

    @objc
    private func didTapSend() {
        // Generate the attachments once, so that any changes we
        // make below are reflected afterwards.
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalVC in
            self.outputAttachmentsPromise()
                .done(on: DispatchQueue.main) { attachments in
                    AssertIsOnMainThread()
                    modalVC.dismiss {
                        AssertIsOnMainThread()

                        if self.options.contains(.canToggleViewOnce), self.isViewOnceEnabled {
                            for attachment in attachments {
                                attachment.isViewOnceAttachment = true
                            }
                            assert(attachments.count <= 1)
                        }

                        self.approvalDelegate?.attachmentApproval(self, didApproveAttachments: attachments, messageBody: self.attachmentTextToolbar.messageBodyForSending)
                    }
                }.catch { error in
                    AssertIsOnMainThread()
                    owsFailDebug("Error: \(error)")

                    modalVC.dismiss {
                        let actionSheet = ActionSheetController(
                            title: CommonStrings.errorAlertTitle,
                            message: OWSLocalizedString(
                                "ATTACHMENT_APPROVAL_FAILED_TO_EXPORT",
                                comment: "Error that outgoing attachments could not be exported."),
                        )
                        actionSheet.overrideUserInterfaceStyle = .dark
                        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton, style: .default))

                        self.present(actionSheet, animated: true)
                    }
                }
        }
    }

    @objc
    private func didTapPenTool() {
        currentPageViewController?.activatePenTool()
    }

    @objc
    private func didTapCropTool() {
        currentPageViewController?.activateCropTool()
    }
}

// MARK: -

extension AttachmentApprovalViewController: AttachmentTextToolbarDelegate {

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
        UIView.animate(withDuration: 0.2,
                       animations: {
            self.contentDimmerView.alpha = 0
        },
                       completion: { _ in
            self.contentDimmerView.removeFromSuperview()
        })
    }

    @objc
    func didTapContentDimmerView(gesture: UITapGestureRecognizer) {
        _ = bottomToolView.resignFirstResponder()
    }

    func attachmentTextToolbarWillBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        startObservingKeyboardNotifications()
    }

    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        showContentDimmerView()
    }

    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        hideContentDimmerView()
    }

    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar) {
        approvalDelegate?.attachmentApproval(self, didChangeMessageBody: attachmentTextToolbar.messageBodyForSending)
    }

    func attachmentTextToolBarDidChangeHeight(_ attachmentTextToolbar: AttachmentTextToolbar) { }

    private func startObservingKeyboardNotifications() {
        guard !observingKeyboardNotifications else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
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
            let currentPageViewController = currentPageViewController,
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
                }
            )
        } else {
            currentPageViewController.keyboardHeight = keyboardHeight
        }
    }
}

// MARK: - Media Quality Selection Sheet

extension AttachmentApprovalViewController {

    private static let mediaQualityLocalizedString = OWSLocalizedString(
        "ATTACHMENT_APPROVAL_MEDIA_QUALITY_TITLE",
        comment: "Title for the attachment approval media quality sheet"
    )

    @objc
    private func didTapMediaQuality() {
        AssertIsOnMainThread()

        let actionSheet = ActionSheetController()
        actionSheet.overrideUserInterfaceStyle = .dark
        actionSheet.isCancelable = true

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localPhoneNumber = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
        let standardQualityLevel = ImageQualityLevel.remoteDefault(localPhoneNumber: localPhoneNumber)

        let selectionControl = MediaQualitySelectionControl(
            standardQualityLevel: standardQualityLevel,
            currentQualityLevel: outputQualityLevel
        )
        selectionControl.callback = { [weak self, weak actionSheet] qualityLevel in
            self?.outputQualityLevel = qualityLevel
            self?.updateBottomToolView(animated: false)

            if UIAccessibility.isVoiceOverRunning {
                // Dismissing immediately and without animation prevents VoiceOver engine from reading accessibilityLabel again.
                actionSheet?.dismiss(animated: false)
            } else {
                // Dismiss the action sheet with a slight delay so that user has a chance to see the change they made.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    actionSheet?.dismiss(animated: true)
                }
            }
        }

        let titleLabel = UILabel()
        titleLabel.font = .dynamicTypeSubheadlineClamped
        titleLabel.textColor = Theme.darkThemePrimaryColor
        titleLabel.textAlignment = .center
        titleLabel.text = AttachmentApprovalViewController.mediaQualityLocalizedString
        titleLabel.isAccessibilityElement = false
        let titleLabelContainer = UIView()
        titleLabelContainer.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewMargins()

        let margin = OWSTableViewController2.defaultHOuterMargin
        let bottomMargin = view.safeAreaInsets.bottom > 0 ? 0 : margin
        let headerStack = UIStackView(arrangedSubviews: [ selectionControl, titleLabelContainer ])
        headerStack.layoutMargins = UIEdgeInsets(top: margin, leading: margin, bottom: bottomMargin, trailing: margin)
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.spacing = 16
        headerStack.axis = .vertical

        actionSheet.customHeader = headerStack

        presentActionSheet(actionSheet)
    }

    private class MediaQualitySelectionControl: UIView {

        private let buttonQualityStandard: MediaQualityButton

        private let buttonQualityHigh = MediaQualityButton(
            title: ImageQualityLevel.high.localizedString,
            subtitle: OWSLocalizedString(
                "ATTACHMENT_APPROVAL_MEDIA_QUALITY_HIGH_OPTION_SUBTITLE",
                comment: "Subtitle for the 'high' option for media quality."
            )
        )

        private let standardQualityLevel: ImageQualityLevel
        private(set) var qualityLevel: ImageQualityLevel

        var callback: ((ImageQualityLevel) -> Void)?

        init(standardQualityLevel: ImageQualityLevel, currentQualityLevel: ImageQualityLevel) {
            self.standardQualityLevel = standardQualityLevel
            self.qualityLevel = currentQualityLevel

            self.buttonQualityStandard = MediaQualityButton(
                title: standardQualityLevel.localizedString,
                subtitle: OWSLocalizedString(
                    "ATTACHMENT_APPROVAL_MEDIA_QUALITY_STANDARD_OPTION_SUBTITLE",
                    comment: "Subtitle for the 'standard' option for media quality."
                )
            )

            super.init(frame: .zero)

            buttonQualityStandard.block = { [weak self] in
                self?.didSelectQualityLevel(standardQualityLevel)
            }
            addSubview(buttonQualityStandard)
            buttonQualityStandard.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .trailing)

            buttonQualityHigh.block = { [weak self] in
                self?.didSelectQualityLevel(.high)
            }
            addSubview(buttonQualityHigh)
            buttonQualityHigh.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .leading)

            buttonQualityHigh.autoPinWidth(toWidthOf: buttonQualityStandard)
            buttonQualityHigh.autoPinEdge(.leading, to: .trailing, of: buttonQualityStandard, withOffset: 20)

            updateButtonAppearance()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func didSelectQualityLevel(_ qualityLevel: ImageQualityLevel) {
            self.qualityLevel = qualityLevel
            updateButtonAppearance()
            callback?(qualityLevel)
        }

        private func updateButtonAppearance() {
            buttonQualityStandard.isSelected = qualityLevel == standardQualityLevel
            buttonQualityHigh.isSelected = qualityLevel == .high
        }

        private class MediaQualityButton: OWSButton {

            let topLabel: UILabel = {
                let label = UILabel()
                label.textColor = Theme.darkThemePrimaryColor
                label.font = .dynamicTypeFootnoteClamped.medium()
                return label
            }()

            let bottomLabel: UILabel = {
                let label = UILabel()
                label.textColor = Theme.darkThemePrimaryColor
                label.font = .dynamicTypeCaption1Clamped
                label.lineBreakMode = .byWordWrapping
                label.numberOfLines = 0
                return label
            }()

            init(title: String, subtitle: String) {
                super.init(block: { })

                layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 8)

                layer.cornerRadius = 18
                layer.borderWidth = 1
                layer.borderColor = UIColor.clear.cgColor

                topLabel.text = title
                bottomLabel.text = subtitle

                let stackView = UIStackView(arrangedSubviews: [ topLabel, bottomLabel ])
                stackView.alignment = .center
                stackView.axis = .vertical
                stackView.spacing = 2
                stackView.isUserInteractionEnabled = false
                addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()
            }

            required init?(coder aDecoder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var isSelected: Bool {
                didSet { updateAppearance() }
            }

            override var isHighlighted: Bool {
                didSet { updateAppearance() }
            }

            private func updateAppearance() {
                let textColor = isSelected ? UIColor.white : (isHighlighted ? UIColor.ows_whiteAlpha40 : UIColor.ows_whiteAlpha70)
                topLabel.textColor = textColor
                bottomLabel.textColor = textColor
                layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor.clear.cgColor
            }
        }

        // MARK: - VoiceOver

        override var isAccessibilityElement: Bool {
            get { true }
            set { super.isAccessibilityElement = newValue }
        }

        override var accessibilityTraits: UIAccessibilityTraits {
            get { .adjustable }
            set { super.accessibilityTraits = newValue }
        }

        override var accessibilityLabel: String? {
            get { AttachmentApprovalViewController.mediaQualityLocalizedString }
            set { super.accessibilityLabel = newValue }
        }

        override var accessibilityValue: String? {
            get {
                let selectedButton = qualityLevel == .high ? buttonQualityHigh : buttonQualityStandard
                return [ selectedButton.topLabel, selectedButton.bottomLabel ].compactMap { $0.text }.joined(separator: ",")
            }
            set { super.accessibilityValue = newValue }
        }

        override var accessibilityFrame: CGRect {
            get { UIAccessibility.convertToScreenCoordinates(bounds.inset(by: UIEdgeInsets(margin: -4)), in: self) }
            set { super.accessibilityFrame = newValue }
        }

        override func accessibilityActivate() -> Bool {
            callback?(qualityLevel)
            return true
        }

        override func accessibilityIncrement() {
            if qualityLevel == standardQualityLevel {
                qualityLevel = .high
                updateButtonAppearance()
            }
        }

        override func accessibilityDecrement() {
            if qualityLevel == .high {
                qualityLevel = standardQualityLevel
                updateButtonAppearance()
            }
        }
    }
}

extension AttachmentApprovalViewController: BodyRangesTextViewDelegate {

    public func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) { }

    public func textViewDidEndTypingMention(_ textView: BodyRangesTextView) { }

    public func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        return view
    }

    public func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        return bottomToolView.attachmentTextToolbar
    }

    public func textViewMentionPickerPossibleAddresses(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [SignalServiceAddress] {
        return approvalDataSource?.attachmentApprovalMentionableAddresses(tx: tx) ?? []
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
}

// MARK: -

extension AttachmentApprovalViewController: AttachmentPrepViewControllerDelegate {

    func attachmentPrepViewControllerDidRequestUpdateControlsVisibility(_ viewController: AttachmentPrepViewController,
                                                                        completion: ((Bool) -> Void)? = nil) {
        updateControlsVisibility(animated: true, completion: completion)
    }
}

// MARK: GalleryRail

extension AttachmentApprovalItem: GalleryRailItem {

    public func buildRailItemView() -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.image = getThumbnailImage()
        return imageView
    }
}

extension AddMoreRailItem: GalleryRailItem {

    func buildRailItemView() -> UIView {
        let button = RoundMediaButton(
            image: UIImage(imageLiteralResourceName: "plus-square-28"),
            backgroundStyle: .blur
        )
        button.isUserInteractionEnabled = false
        button.layoutMargins = .zero
        button.ows_contentEdgeInsets = .zero
        return button
    }
}

// MARK: -

extension AttachmentApprovalItemCollection: GalleryRailItemProvider {

    var railItems: [GalleryRailItem] {
        if isAddMoreVisible() {
            return self.attachmentApprovalItems + [AddMoreRailItem()]
        } else {
            return self.attachmentApprovalItems
        }
    }
}

// MARK: -

extension AttachmentApprovalViewController: GalleryRailViewDelegate {

    public func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem) {
        if imageRailItem is AddMoreRailItem {
            didTapAddMedia()
            return
        }

        guard let targetItem = imageRailItem as? AttachmentApprovalItem else {
            owsFailDebug("unexpected imageRailItem: \(imageRailItem)")
            return
        }

        guard let currentItem = currentItem,
              let currentIndex = attachmentApprovalItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return
        }

        guard let targetIndex = attachmentApprovalItems.firstIndex(of: targetItem) else {
            owsFailDebug("targetIndex was unexpectedly nil")
            return
        }

        let direction: UIPageViewController.NavigationDirection = currentIndex < targetIndex ? .forward : .reverse
        setCurrentItem(targetItem, direction: direction, animated: true)
    }
}

// MARK: -

extension AttachmentApprovalViewController: ApprovalRailCellViewDelegate {

    func approvalRailCellView(_ approvalRailCellView: ApprovalRailCellView, didRemoveItem attachmentApprovalItem: AttachmentApprovalItem) {
        remove(attachmentApprovalItem: attachmentApprovalItem)
    }

    func canRemoveApprovalRailCellView(_ approvalRailCellView: ApprovalRailCellView) -> Bool {
        return self.attachmentApprovalItems.count > 1
    }
}

// MARK: -

private enum SaveableAsset {
    case image(_ image: UIImage)
    case imageUrl(_ url: URL)
    case videoUrl(_ url: URL)
}

private extension SaveableAsset {
    init(attachmentApprovalItem: AttachmentApprovalItem) throws {
        if let imageEditorModel = attachmentApprovalItem.imageEditorModel {
            try self.init(imageEditorModel: imageEditorModel)
        } else {
            try self.init(attachment: attachmentApprovalItem.attachment)
        }
    }

    private init(imageEditorModel: ImageEditorModel) throws {
        guard let image = imageEditorModel.renderOutput() else {
            throw OWSAssertionError("failed to render image")
        }

        self = .image(image)
    }

    private init(attachment: SignalAttachment) throws {
        if attachment.isValidImage {
            guard let imageUrl = attachment.dataUrl else {
                throw OWSAssertionError("imageUrl was unexpectedly nil")
            }

            self = .imageUrl(imageUrl)
        } else if attachment.isValidVideo {
            guard let videoUrl = attachment.dataUrl else {
                throw OWSAssertionError("videoUrl was unexpectedly nil")
            }

            self = .videoUrl(videoUrl)
        } else {
            throw OWSAssertionError("unsaveable media")
        }
    }
}
