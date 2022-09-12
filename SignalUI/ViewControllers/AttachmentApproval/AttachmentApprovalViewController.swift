//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import Photos
import CoreServices
import SignalMessaging

public protocol AttachmentApprovalViewControllerDelegate: AnyObject {

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?)

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController)

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didChangeMessageBody newMessageBody: MessageBody?)

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment)

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController)
}

public protocol AttachmentApprovalViewControllerDataSource: AnyObject {

    var attachmentApprovalTextInputContextIdentifier: String? { get }

    var attachmentApprovalRecipientNames: [String] { get }

    var attachmentApprovalMentionableAddresses: [SignalServiceAddress] { get }
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
    public static let canChangeQualityLevel = AttachmentApprovalViewControllerOptions(rawValue: 1 << 3)
    public static let isNotFinalScreen = AttachmentApprovalViewControllerOptions(rawValue: 1 << 4)
}

// MARK: -

@objc
public class AttachmentApprovalViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    // MARK: - Properties

    private let receivedOptions: AttachmentApprovalViewControllerOptions

    private var options: AttachmentApprovalViewControllerOptions {
        var options = receivedOptions

        if attachmentApprovalItemCollection.attachmentApprovalItems.count == 1,
            let firstItem = attachmentApprovalItemCollection.attachmentApprovalItems.first,
            firstItem.attachment.isValidImage || firstItem.attachment.isValidVideo {
            options.insert(.canToggleViewOnce)
        }

        if ImageQualityLevel.max == .high && attachmentApprovalItemCollection.attachmentApprovalItems.filter({ $0.attachment.isValidImage }).count > 0 {
            options.insert(.canChangeQualityLevel)
        }

        return options
    }

    var isAddMoreVisible: Bool {
        return options.contains(.canAddMore) && !isViewOnceEnabled
    }

    var isViewOnceEnabled = false

    lazy var outputQualityLevel: ImageQualityLevel = databaseStorage.read { .default(transaction: $0) }

    public weak var approvalDelegate: AttachmentApprovalViewControllerDelegate?
    public weak var approvalDataSource: AttachmentApprovalViewControllerDataSource?

    // MARK: - Initializers

    @available(*, unavailable, message: "use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let kSpacingBetweenItems: CGFloat = 20

    private var observerToken: NSObjectProtocol?

    required public init(options: AttachmentApprovalViewControllerOptions,
                         attachmentApprovalItems: [AttachmentApprovalItem]) {
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

        // This fixes an issue with keyboard flashing white while being dismissed.
        if #available(iOS 13, *) {
            overrideUserInterfaceStyle = .dark
        }

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

    public class func wrappedInNavController(attachments: [SignalAttachment],
                                             initialMessageBody: MessageBody?,
                                             approvalDelegate: AttachmentApprovalViewControllerDelegate,
                                             approvalDataSource: AttachmentApprovalViewControllerDataSource)
        -> OWSNavigationController {

        let attachmentApprovalItems = attachments.map { AttachmentApprovalItem(attachment: $0, canSave: false) }
        let vc = AttachmentApprovalViewController(options: [.hasCancel], attachmentApprovalItems: attachmentApprovalItems)
        vc.messageBody = initialMessageBody
        vc.approvalDelegate = approvalDelegate
        vc.approvalDataSource = approvalDataSource
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
    private var bottomToolViewBottomConstraint: NSLayoutConstraint?

    private lazy var inputAccessoryPlaceholder: InputAccessoryViewPlaceholder = {
        let placeholder = InputAccessoryViewPlaceholder()
        placeholder.delegate = self
        placeholder.referenceView = view
        return placeholder
    }()

    lazy var contentDimmerView: UIView = {
        let dimmerView = UIView()
        dimmerView.backgroundColor = .ows_blackAlpha40
        return dimmerView
    }()

    // MARK: - View Lifecycle

    public override var prefersStatusBarHidden: Bool {
        !UIDevice.current.hasIPhoneXNotch && !UIDevice.current.isIPad && !CurrentAppContext().hasActiveCall
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        // avoid an unpleasant "bounce" which doesn't make sense in the context of a single item.
        pagerScrollView?.isScrollEnabled = attachmentApprovalItems.count > 1

        // Bottom Toolbar
        galleryRailView.delegate = self

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

        // Bottom Bar
        bottomToolView.attachmentTextToolbarDelegate = self
        attachmentTextToolbar.mentionTextViewDelegate = self

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
        bottomToolView.autoPinWidthToSuperview()
        bottomToolViewBottomConstraint = bottomToolView.autoPinEdge(toSuperviewEdge: .bottom)

        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        Logger.debug("")
        super.viewWillAppear(animated)

        UIViewController.attemptRotationToDeviceOrientation()

        topBar.update(withRecipientNames: approvalDataSource?.attachmentApprovalRecipientNames ?? [])

        updateContents(animated: false)

        if let currentPageViewController = currentPageViewController {
            self.updateContentLayoutMargins(for: currentPageViewController)
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
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        if let currentPageViewController = currentPageViewController {
            self.updateContentLayoutMargins(for: currentPageViewController)
        }
    }

    private func updateContentLayoutMargins(for viewController: AttachmentPrepViewController) {
        // The goal of all this layout logic is to lay out content in Review screen
        // the same way it will be laid out in Edit mode (drawing etc) so that activating editing tools
        // does not create any changes to media's size and position.
        // However AttachmentPrepViewController's view is always full screen and is managed by UIPageViewController,
        // which makes it not possible to constrain any of its subviews to the bottom toolbar.
        // The solution is to allow to set layout margins in AttachmentPrepViewController's view externally,
        // which is achieved through use of AttachmentPrepContentView.contentLayoutMargins.

        var contentLayoutMargins: UIEdgeInsets = .zero
        // On devices with a screen notch at the top content is constrained to safe area inset so that status bar is visible.
        // On all other devices content is pinned to the top of the screen (status bar is hidden on those devices).
        if UIDevice.current.hasIPhoneXNotch {
            contentLayoutMargins.top = view.safeAreaInsets.top
        }

        // Generally it is necessary to constrain bottom of the content in the current page to the top
        // of bottom toolbar in review screen. However, for images we have "edit" mode and we want
        // the bottom margin to not change when switching to/from "edit" mode, with edit mode toolbar's height
        // being the one to be used in the review screen.
        if let mediaEditingToolbarHeight = viewController.mediaEditingToolbarHeight {
            contentLayoutMargins.bottom = mediaEditingToolbarHeight
        } else {
            // bottomToolView contains UIStackView that doesn't always have a final frame at this point.
            bottomToolView.layoutIfNeeded()
            contentLayoutMargins.bottom = bottomToolView.opaqueAreaHeight
            if let supplementaryView = viewController.toolbarSupplementaryView {
                contentLayoutMargins.bottom += supplementaryView.height
            }
        }
        contentLayoutMargins.bottom += view.safeAreaInsets.bottom

        viewController.contentView.contentLayoutMargins = contentLayoutMargins
    }

    private func updateContents(animated: Bool) {
        updateBottomToolView(animated: animated)
        updateMediaRail(animated: animated)
    }

    // MARK: - Input Accessory

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    public override var inputAccessoryView: UIView? {
        return inputAccessoryPlaceholder
    }

    public override var textInputContextIdentifier: String? {
        return approvalDataSource?.attachmentApprovalTextInputContextIdentifier
    }

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

        let doneButtonAssetResourceName = options.contains(.isNotFinalScreen) ? "arrow-right-24" : "send-solid-24"
        let configuration =
        AttachmentApprovalToolbar.Configuration(isAddMoreVisible: isAddMoreVisible,
                                                isMediaStripVisible: attachmentApprovalItems.count > 1,
                                                isMediaHighQualityEnabled: outputQualityLevel == .high,
                                                isViewOnceOn: isViewOnceEnabled,
                                                canToggleViewOnce: options.contains(.canToggleViewOnce),
                                                canChangeMediaQuality: options.contains(.canChangeQualityLevel),
                                                canSaveMedia: currentPageViewController.canSaveMedia,
                                                doneButtonAssetResourceName: doneButtonAssetResourceName)
        bottomToolView.update(currentAttachmentItem: currentPageViewController.attachmentApprovalItem,
                              configuration: configuration,
                              animated: animated)
    }

    public var messageBody: MessageBody? {
        get {
            return attachmentTextToolbar.messageBody
        }
        set {
            attachmentTextToolbar.messageBody = newValue
        }
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
                owsFailDebug("removing last item shouldn't be possible because rail should not be visible")
                return
            }
        }

        guard let cell = galleryRailView.cellViews.first(where: { cellView in
            guard let item = cellView.item else { return false }
            return item.isEqualToGalleryRailItem(attachmentApprovalItem)
        }) else {
            owsFailDebug("cell was unexpectedly nil")
            return
        }

        attachmentApprovalItemCollection.remove(item: attachmentApprovalItem)
        approvalDelegate?.attachmentApproval(self, didRemoveAttachment: attachmentApprovalItem.attachment)

        // Special logic if there is just one item after deletion.
        // Fade out the entire rail view because it won't be visible after animations complete.
        guard attachmentApprovalItems.count > 1 else {
            updateContents(animated: true)
            return
        }

        // If rail view is still be visible after deletion it looks better
        // if cell for deleted item is faded out.
        UIView.animate(withDuration: 0.15,
                       animations: {
            cell.isHidden = true
            cell.alpha = 0
        },
                       completion: { _ in
            self.updateContents(animated: true)
        })
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

        // Pause video playback for current page
        currentPageViewController?.prepareToMoveOffscreen()

        assert(pendingViewControllers.count == 1)
        pendingViewControllers.forEach { viewController in
            guard let pendingPage = viewController as? AttachmentPrepViewController else {
                owsFailDebug("unexpected viewController: \(viewController)")
                return
            }

            // use compact scale when keyboard is popped.
            let scale: AttachmentPrepViewController.AttachmentViewScale = self.bottomToolView.isEditingMediaMessage ? .compact : .fullsize
            pendingPage.setAttachmentViewScale(scale, animated: false)
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
        guard let viewController = AttachmentPrepViewController.viewController(for: item) else {
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

        // Pause video playback for current page
        currentPageViewController?.prepareToMoveOffscreen()

        page.loadViewIfNeeded()
        updateContentLayoutMargins(for: page)

        Logger.debug("currentItem for attachment: \(item.attachment.debugDescription)")
        setViewControllers([page], direction: direction, animated: animated)

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

        guard let currentItem = self.currentItem else {
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
            promises.append(outputAttachmentPromise(for: attachmentApprovalItem).map(on: .global()) { attachment in
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
            return renderedAttachmentPromise(videoEditorModel: videoEditorModel,
                                             attachmentApprovalItem: attachmentApprovalItem)
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
        }.map(on: .global()) { (dstImage: UIImage) -> SignalAttachment in
            var dataUTI = kUTTypeImage as String
            guard let dstData: Data = {
                let isLossy: Bool = attachmentApprovalItem.attachment.mimeType.caseInsensitiveCompare(OWSMimeTypeImageJpeg) == .orderedSame
                if isLossy {
                    dataUTI = kUTTypeJPEG as String
                    return dstImage.jpegData(compressionQuality: 0.9)
                } else {
                    dataUTI = kUTTypePNG as String
                    return dstImage.pngData()
                }
                }() else {
                    owsFailDebug("Could not export for output.")
                    return attachmentApprovalItem.attachment
            }
            guard let dataSource = DataSourceValue.dataSource(with: dstData, utiType: dataUTI) else {
                owsFailDebug("Could not prepare data source for output.")
                return attachmentApprovalItem.attachment
            }

            // Rewrite the filename's extension to reflect the output file format.
            var filename: String? = attachmentApprovalItem.attachment.sourceFilename
            if let sourceFilename = attachmentApprovalItem.attachment.sourceFilename {
                if let fileExtension: String = MIMETypeUtil.fileExtension(forUTIType: dataUTI) {
                    filename = (sourceFilename as NSString).deletingPathExtension.appendingFileExtension(fileExtension)
                }
            }
            dataSource.sourceFilename = filename

            let dstAttachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataUTI)
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
    func renderedAttachmentPromise(videoEditorModel: VideoEditorModel,
                                   attachmentApprovalItem: AttachmentApprovalItem) -> Promise<SignalAttachment> {
        assert(videoEditorModel.needsRender)
        return videoEditorModel.ensureCurrentRender().result.map(on: .sharedUserInitiated) { result in
            let filePath = try result.consumeResultPath()
            guard let fileExtension = filePath.fileExtension else {
                throw OWSAssertionError("Missing fileExtension.")
            }
            guard let dataUTI = MIMETypeUtil.utiType(forFileExtension: fileExtension) else {
                throw OWSAssertionError("Missing dataUTI.")
            }
            let dataSource = try DataSourcePath.dataSource(withFilePath: filePath, shouldDeleteOnDeallocation: true)
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
        self.approvalDelegate?.attachmentApprovalDidCancel(self)
    }

    @objc
    private func navigateBackPressed() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func didTapSave() {
        guard let currentItem = currentItem else { return }

        let errorText = OWSLocalizedString("ATTACHMENT_APPROVAL_FAILED_TO_SAVE",
                                           comment: "alert text when Signal was unable to save a copy of the attachment to the system photo library")
        do {
            let saveableAsset: SaveableAsset = try SaveableAsset(attachmentApprovalItem: currentItem)

            self.ows_askForMediaLibraryPermissions { isGranted in
                guard isGranted else {
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    switch saveableAsset {
                    case .image(let image):
                        PHAssetCreationRequest.creationRequestForAsset(from: image)
                    case .imageUrl(let imageUrl):
                        PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: imageUrl)
                    case .videoUrl(let videoUrl):
                        PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: videoUrl)
                    }
                }, completionHandler: { didSucceed, error in
                    DispatchQueue.main.async {
                        if didSucceed {
                            let toastController = ToastController(text: OWSLocalizedString("ATTACHMENT_APPROVAL_MEDIA_DID_SAVE",
                                                                                           comment: "toast alert shown after user taps the 'save' button"))
                            let inset = self.bottomToolView.height + 16
                            toastController.presentToastView(from: .bottom, of: self.view, inset: inset)
                        } else {
                            owsFailDebug("error: \(String(describing: error))")
                            OWSActionSheets.showErrorAlert(message: errorText)
                        }
                    }
                })
            }
        } catch {
            owsFailDebug("error: \(error)")
            OWSActionSheets.showErrorAlert(message: errorText)
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
        preferences.setWasViewOnceTooltipShown()

        updateBottomToolView(animated: true)
    }

    @objc
    private func didTapSend() {
        // Toolbar flickers in and out if there are errors
        // and remains visible momentarily after share extension is dismissed.
        // It's easiest to just hide it at this point since we're done with it.
        currentPageViewController?.shouldAllowAttachmentViewResizing = false

        // Generate the attachments once, so that any changes we
        // make below are reflected afterwards.
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modalVC in
            self.outputAttachmentsPromise()
                .done(on: .main) { attachments in
                    AssertIsOnMainThread()
                    modalVC.dismiss {
                        AssertIsOnMainThread()

                        if self.options.contains(.canToggleViewOnce), self.isViewOnceEnabled {
                            for attachment in attachments {
                                attachment.isViewOnceAttachment = true
                            }
                            assert(attachments.count <= 1)
                        }

                        self.approvalDelegate?.attachmentApproval(self, didApproveAttachments: attachments, messageBody: self.attachmentTextToolbar.messageBody)
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
                            theme: .translucentDark)
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

    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        currentPageViewController?.setAttachmentViewScale(.compact, animated: true)
        showContentDimmerView()
    }

    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        currentPageViewController?.setAttachmentViewScale(.fullsize, animated: true)
        hideContentDimmerView()
    }

    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar) {
        approvalDelegate?.attachmentApproval(self, didChangeMessageBody: attachmentTextToolbar.messageBody)
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

        let actionSheet = ActionSheetController(theme: .translucentDark)
        actionSheet.isCancelable = true

        let selectionControl = MediaQualitySelectionControl(currentQualityLevel: outputQualityLevel)
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
        titleLabel.font = .ows_dynamicTypeSubheadlineClamped
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

        private let buttonQualityStandard = MediaQualityButton(
            title: ImageQualityLevel.standard.localizedString,
            subtitle: OWSLocalizedString(
                "ATTACHMENT_APPROVAL_MEDIA_QUALITY_STANDARD_OPTION_SUBTITLE",
                comment: "Subtitle for the 'standard' option for media quality."
            )
        )

        private let buttonQualityHigh = MediaQualityButton(
            title: ImageQualityLevel.high.localizedString,
            subtitle: OWSLocalizedString(
                "ATTACHMENT_APPROVAL_MEDIA_QUALITY_HIGH_OPTION_SUBTITLE",
                comment: "Subtitle for the 'high' option for media quality."
            )
        )

        private(set) var qualityLevel: ImageQualityLevel

        var callback: ((ImageQualityLevel) -> Void)?

        init(currentQualityLevel: ImageQualityLevel) {
            qualityLevel = currentQualityLevel
            super.init(frame: .zero)

            buttonQualityStandard.block = { [weak self] in
                self?.didSelectQualityLevel(.standard)
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
            buttonQualityStandard.isSelected = qualityLevel == .standard
            buttonQualityHigh.isSelected = qualityLevel == .high
        }

        private class MediaQualityButton: OWSButton {

            let topLabel: UILabel = {
                let label = UILabel()
                label.textColor = Theme.darkThemePrimaryColor
                label.font = .ows_dynamicTypeFootnoteClamped.ows_medium
                return label
            }()

            let bottomLabel: UILabel = {
                let label = UILabel()
                label.textColor = Theme.darkThemePrimaryColor
                label.font = .ows_dynamicTypeCaption1Clamped
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
                let selectedButton = qualityLevel == .standard ? buttonQualityStandard : buttonQualityHigh
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
            if qualityLevel == .standard {
                qualityLevel = .high
                updateButtonAppearance()
            }
        }

        override func accessibilityDecrement() {
            if qualityLevel == .high {
                qualityLevel = .standard
                updateButtonAppearance()
            }
        }
    }
}

extension AttachmentApprovalViewController: MentionTextViewDelegate {

    public func textViewDidBeginTypingMention(_ textView: MentionTextView) { }

    public func textViewDidEndTypingMention(_ textView: MentionTextView) { }

    public func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        return view
    }

    public func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        return bottomToolView.attachmentTextToolbar
    }

    public func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        return approvalDataSource?.attachmentApprovalMentionableAddresses ?? []
    }

    public func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {}

    public func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .composingAttachment
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
        let button = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-add-photos"), backgroundStyle: .blur)
        button.isUserInteractionEnabled = false
        button.layoutMargins = .zero
        button.contentEdgeInsets = .zero
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

extension AttachmentApprovalViewController: InputAccessoryViewPlaceholderDelegate {

    public func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidPresent() {
        updateBottomToolViewPosition()
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidDismiss() {
        updateBottomToolViewPosition()
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissingInteractively() {
        updateBottomToolViewPosition()
    }

    func handleKeyboardStateChange(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        guard animationDuration > 0 else { return updateBottomToolViewPosition() }

        UIView.beginAnimations("keyboardStateChange", context: nil)
        UIView.setAnimationBeginsFromCurrentState(true)
        UIView.setAnimationCurve(animationCurve)
        UIView.setAnimationDuration(animationDuration)
        updateBottomToolViewPosition()
        UIView.commitAnimations()
    }

    func updateBottomToolViewPosition() {
        bottomToolViewBottomConstraint?.constant = -inputAccessoryPlaceholder.keyboardOverlap

        // We always want to apply the new bottom bar position immediately,
        // as this only happens during animations (interactive or otherwise)
        bottomToolView.superview?.layoutIfNeeded()
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

    init(imageEditorModel: ImageEditorModel) throws {
        guard let image = imageEditorModel.renderOutput() else {
            throw OWSAssertionError("failed to render image")
        }

        self = .image(image)
    }

    init(attachment: SignalAttachment) throws {
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
