//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import Photos
import PromiseKit

@objc
public protocol AttachmentApprovalViewControllerDelegate: class {
    // In the media send flow, partially swiping to go back from AttachmentApproval,
    // then cancelling would render the mediaSend bottom buttons behind the attachment approval
    // input toolbar.
    //
    // I erroneously thought that this would have been prevented the UINavigationControllerDelegate
    // `didShowViewController` method but `didShowViewController" is not called upon canceling
    // navigation, while that view controllers `didAppear` method is.
    func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController)

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didApproveAttachments attachments: [SignalAttachment], messageText: String?)

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController)

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didChangeMessageText newMessageText: String?)

    @objc
    optional func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment)

    @objc
    optional func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController)

    @objc
    optional func attachmentApprovalBackButtonTitle() -> String
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
}

// MARK: -

@objc
public class AttachmentApprovalViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    // MARK: - Dependencies

    private var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    // MARK: - Properties

    private let receivedOptions: AttachmentApprovalViewControllerOptions

    private var options: AttachmentApprovalViewControllerOptions {
        var options = receivedOptions

        // For now, only still images can be sent as view-once messages.
        if FeatureFlags.viewOnceSending,
            attachmentApprovalItemCollection.attachmentApprovalItems.count == 1,
            let firstItem = attachmentApprovalItemCollection.attachmentApprovalItems.first,
            firstItem.attachment.isValidImage {
            options.insert(.canToggleViewOnce)
        }

        return options
    }

    var isAddMoreVisible: Bool {
        return options.contains(.canAddMore) && !preferences.isViewOnceMessagesEnabled()
    }

    public weak var approvalDelegate: AttachmentApprovalViewControllerDelegate?

    public var isEditingCaptions = false {
        didSet {
            updateContents(isApproved: false)
        }
    }

    // MARK: - Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    let kSpacingBetweenItems: CGFloat = 20

    required public init(options: AttachmentApprovalViewControllerOptions,
                         sendButtonImageName: String,
                         attachmentApprovalItems: [AttachmentApprovalItem]) {
        assert(attachmentApprovalItems.count > 0)
        self.receivedOptions = options
        self.bottomToolView = AttachmentApprovalInputAccessoryView(options: options, sendButtonImageName: sendButtonImageName)

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
        bottomToolView.delegate = self

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    public class func wrappedInNavController(attachments: [SignalAttachment],
                                             approvalDelegate: AttachmentApprovalViewControllerDelegate)
        -> OWSNavigationController {

        let attachmentApprovalItems = attachments.map { AttachmentApprovalItem(attachment: $0, canSave: false) }
        let vc = AttachmentApprovalViewController(options: [.hasCancel],
                                                  sendButtonImageName: "send-solid-24",
                                                  attachmentApprovalItems: attachmentApprovalItems)
        vc.approvalDelegate = approvalDelegate
        let navController = OWSNavigationController(rootViewController: vc)
        navController.ows_prefersStatusBarHidden = true

        guard let navigationBar = navController.navigationBar as? OWSNavigationBar else {
            owsFailDebug("navigationBar was nil or unexpected class")
            return navController
        }
        navigationBar.overrideTheme(type: .clear)

        return navController
    }

    // MARK: - Notifications

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        updateContents(isApproved: false)
    }

    // MARK: - Subviews

    var galleryRailView: GalleryRailView {
        return bottomToolView.galleryRailView
    }

    var attachmentTextToolbar: AttachmentTextToolbar {
        return bottomToolView.attachmentTextToolbar
    }

    let bottomToolView: AttachmentApprovalInputAccessoryView

    lazy var touchInterceptorView = UIView()

    // MARK: - View Lifecycle

    public override var prefersStatusBarHidden: Bool {
        guard !OWSWindowManager.shared().hasCall() else {
            return false
        }

        return true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .black

        // avoid an unpleasant "bounce" which doesn't make sense in the context of a single item.
        pagerScrollView?.isScrollEnabled = attachmentApprovalItems.count > 1

        // Bottom Toolbar
        galleryRailView.delegate = self
        attachmentTextToolbar.attachmentTextToolbarDelegate = self

        // Navigation

        self.navigationItem.title = nil

        guard let firstItem = attachmentApprovalItems.first else {
            owsFailDebug("firstItem was unexpectedly nil")
            return
        }

        self.setCurrentItem(firstItem, direction: .forward, animated: false)

        // layout immediately to avoid animating the layout process during the transition
        self.currentPageViewController.view.layoutIfNeeded()

        view.addSubview(touchInterceptorView)
        touchInterceptorView.autoPinEdgesToSuperviewEdges()
        touchInterceptorView.isHidden = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapTouchInterceptorView(gesture:)))
        touchInterceptorView.addGestureRecognizer(tapGesture)
    }

    override public func viewWillAppear(_ animated: Bool) {
        Logger.debug("")
        super.viewWillAppear(animated)

        guard let navigationBar = navigationController?.navigationBar as? OWSNavigationBar else {
            owsFailDebug("navigationBar was nil or unexpected class")
            return
        }
        navigationBar.overrideTheme(type: .clear)

        updateContents(isApproved: false)
    }

    override public func viewDidAppear(_ animated: Bool) {
        Logger.debug("")

        super.viewDidAppear(animated)
        updateContents(isApproved: false)
        approvalDelegate?.attachmentApprovalDidAppear(self)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        Logger.debug("")
        super.viewWillDisappear(animated)
    }

    private func updateContents(isApproved: Bool) {
        updateNavigationBar()
        updateInputAccessory(isApproved: isApproved)

        touchInterceptorView.isHidden = !isEditingCaptions

        updateMediaRail()
        bottomToolView.options = options
    }

    // MARK: - Input Accessory

    override public var inputAccessoryView: UIView? {
        bottomToolView.layoutIfNeeded()
        return bottomToolView
    }

    override public var canBecomeFirstResponder: Bool {
        return !shouldHideControls
    }

    public func updateInputAccessory(isApproved: Bool) {
        var currentPageViewController: AttachmentPrepViewController?
        if pageViewControllers.count == 1 {
            currentPageViewController = pageViewControllers.first
        }
        let currentAttachmentItem: AttachmentApprovalItem? = currentPageViewController?.attachmentApprovalItem

        let hasPresentedView = self.presentedViewController != nil
        let isToolbarFirstResponder = bottomToolView.hasFirstResponder
        if !shouldHideControls, !isFirstResponder, !hasPresentedView, !isToolbarFirstResponder {
            becomeFirstResponder()
        }

        bottomToolView.update(isEditingCaptions: isEditingCaptions,
                              currentAttachmentItem: currentAttachmentItem,
                              shouldHideControls: shouldHideControls,
                              isApproved: isApproved)
    }

    public var messageText: String? {
        get {
            return attachmentTextToolbar.messageText
        }
        set {
            attachmentTextToolbar.messageText = newValue
        }
    }

    // MARK: - Navigation Bar

    lazy var saveButton: UIView = {
        return OWSButton.navigationBarButton(imageName: "download-outline-28") { [weak self] in
            self?.didTapSave()
        }
    }()

    public func updateNavigationBar() {
        guard !shouldHideControls else {
            self.navigationItem.leftBarButtonItem = nil
            self.navigationItem.rightBarButtonItem = nil
            return
        }

        guard !isEditingCaptions else {
            // Hide all navigation bar items while the caption view is open.
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("ATTACHMENT_APPROVAL_CAPTION_TITLE", comment: "Title for 'caption' mode of the attachment approval view."), style: .plain, target: nil, action: nil)

            let doneButton = navigationBarButton(imageName: "image_editor_checkmark_full",
                                                 selector: #selector(didTapCaptionDone(sender:)))
            let navigationBarItems = [doneButton]
            updateNavigationBar(navigationBarItems: navigationBarItems)
            return
        }

        var navigationBarItems = [UIView]()

        if let viewControllers = viewControllers,
            viewControllers.count == 1,
            let firstViewController = viewControllers.first as? AttachmentPrepViewController {
            navigationBarItems.append(contentsOf: firstViewController.navigationBarItems())
            if firstViewController.attachmentApprovalItem.canSave {
                navigationBarItems.append(saveButton)
            }

            // Show the caption UI if there's more than one attachment
            // OR if the attachment already has a caption.
            let attachmentCount = attachmentApprovalItemCollection.count
            var shouldShowCaptionUI = attachmentCount > 1
            if let captionText = firstViewController.attachmentApprovalItem.captionText, captionText.count > 0 {
                shouldShowCaptionUI = true
            }
            if shouldShowCaptionUI {
                let addCaptionButton = navigationBarButton(imageName: "image_editor_add_caption",
                                                           selector: #selector(didTapCaption(sender:)))
                navigationBarItems.append(addCaptionButton)
            }
        }

        updateNavigationBar(navigationBarItems: navigationBarItems)

        if options.contains(.hasCancel) {
            // Mimic a UIBarButtonItem of type .cancel, but with a shadow.
            let cancelButton = OWSButton(title: CommonStrings.cancelButton) { [weak self] in
                self?.cancelPressed()
            }
            cancelButton.setTitleColor(.white, for: .normal)
            if let titleLabel = cancelButton.titleLabel {
                titleLabel.font = UIFont.systemFont(ofSize: 18.0)
                titleLabel.layer.shadowColor = UIColor.black.cgColor
                titleLabel.layer.shadowRadius = 2.0
                titleLabel.layer.shadowOpacity = 0.66
                titleLabel.layer.shadowOffset = .zero
            } else {
                owsFailDebug("Missing titleLabel.")
            }
            cancelButton.sizeToFit()
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: cancelButton)
        } else {
            // Mimic a conventional back button, but with a shadow.
            let isRTL = CurrentAppContext().isRTL
            let imageName = isRTL ? "NavBarBackRTL" : "NavBarBack"
            let backButton = OWSButton(imageName: imageName, tintColor: .white) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            if let backButtonTitle = approvalDelegate?.attachmentApprovalBackButtonTitle?() {
                backButton.setTitle(backButtonTitle, for: .normal)
            }

            // Nudge closer to the left edge to match default back button item.
            let kExtraLeftPadding: CGFloat = isRTL ? +0 : -8

            // Give some extra hit area to the back button.
            let kExtraRightPadding: CGFloat = isRTL ? -0 : +30

            // Extra hit area above/below
            let kExtraHeightPadding: CGFloat = 4

            // Matching the default backbutton placement is tricky.
            // We can't just adjust the imageEdgeInsets on a UIBarButtonItem directly,
            // so we adjust the imageEdgeInsets on a UIButton, then wrap that
            // in a UIBarButtonItem.

            backButton.contentHorizontalAlignment = .left

            // Default back button is 1.5 pixel lower than our extracted image.
            let kTopInsetPadding: CGFloat = 1.5
            backButton.imageEdgeInsets = UIEdgeInsets(top: kTopInsetPadding, left: kExtraLeftPadding, bottom: 0, right: 0)

            var backImageSize = CGSize.zero
            if let backImage = UIImage(named: imageName) {
                backImageSize = backImage.size
            } else {
                owsFailDebug("Missing backImage.")
            }
            backButton.frame = CGRect(origin: .zero, size: CGSize(width: backImageSize.width + kExtraRightPadding,
                                                                  height: backImageSize.height + kExtraHeightPadding))

            backButton.layer.shadowColor = UIColor.black.cgColor
            backButton.layer.shadowRadius = 2.0
            backButton.layer.shadowOpacity = 0.66
            backButton.layer.shadowOffset = .zero
            // Note: using a custom leftBarButtonItem breaks the interactive pop gesture.
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backButton)
        }
    }

    // MARK: - Control Visibility

    public var shouldHideControls: Bool {
        guard let pageViewController = pageViewControllers.first else {
            return false
        }
        return pageViewController.shouldHideControls
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

        UIView.animate(withDuration: 0.2,
                       animations: {
                        // shrink stack view item until it disappears
                        cell.isHidden = true

                        // simultaneously fade out
                        cell.alpha = 0
        },
                       completion: { _ in
                        self.attachmentApprovalItemCollection.remove(item: attachmentApprovalItem)
                        self.approvalDelegate?.attachmentApproval?(self, didRemoveAttachment: attachmentApprovalItem.attachment)
                        self.updateMediaRail()
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

    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        Logger.debug("")

        assert(pendingViewControllers.count == 1)
        pendingViewControllers.forEach { viewController in
            guard let pendingPage = viewController as? AttachmentPrepViewController else {
                owsFailDebug("unexpected viewController: \(viewController)")
                return
            }

            // use compact scale when keyboard is popped.
            let scale: AttachmentPrepViewController.AttachmentViewScale = self.isFirstResponder ? .fullsize : .compact
            pendingPage.setAttachmentViewScale(scale, animated: false)
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted: Bool) {
        Logger.debug("")

        assert(previousViewControllers.count == 1)
        previousViewControllers.forEach { viewController in
            guard let previousPage = viewController as? AttachmentPrepViewController else {
                owsFailDebug("unexpected viewController: \(viewController)")
                return
            }

            if transitionCompleted {
                previousPage.zoomOut(animated: false)
                updateMediaRail()
            }
        }
    }

    // MARK: - UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let currentViewController = viewController as? AttachmentPrepViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        let currentItem = currentViewController.attachmentApprovalItem
        guard let previousItem = attachmentApprovalItem(before: currentItem) else {
            return nil
        }

        guard let previousPage: AttachmentPrepViewController = buildPage(item: previousItem) else {
            return nil
        }

        return previousPage
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("")

        guard let currentViewController = viewController as? AttachmentPrepViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        let currentItem = currentViewController.attachmentApprovalItem
        guard let nextItem = attachmentApprovalItem(after: currentItem) else {
            return nil
        }

        guard let nextPage: AttachmentPrepViewController = buildPage(item: nextItem) else {
            return nil
        }

        return nextPage
    }

    public var currentPageViewController: AttachmentPrepViewController {
        return pageViewControllers.first!
    }

    public var pageViewControllers: [AttachmentPrepViewController] {
        return super.viewControllers!.map { $0 as! AttachmentPrepViewController }
    }

    @objc
    public override func setViewControllers(_ viewControllers: [UIViewController]?, direction: UIPageViewController.NavigationDirection, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        super.setViewControllers(viewControllers,
                                 direction: direction,
                                 animated: animated) { [weak self] (finished) in
                                    if let completion = completion {
                                        completion(finished)
                                    }
                                    self?.updateContents(isApproved: false)
        }
    }

    var currentItem: AttachmentApprovalItem! {
        get {
            return currentPageViewController.attachmentApprovalItem
        }
        set {
            setCurrentItem(newValue, direction: .forward, animated: false)
        }
    }

    private var cachedPages: [AttachmentApprovalItem: AttachmentPrepViewController] = [:]
    private func buildPage(item: AttachmentApprovalItem) -> AttachmentPrepViewController? {

        if let cachedPage = cachedPages[item] {
            Logger.debug("cache hit.")
            return cachedPage
        }

        Logger.debug("cache miss.")
        let viewController = AttachmentPrepViewController(attachmentApprovalItem: item)
        viewController.prepDelegate = self
        cachedPages[item] = viewController

        return viewController
    }

    private func setCurrentItem(_ item: AttachmentApprovalItem, direction: UIPageViewController.NavigationDirection, animated isAnimated: Bool) {
        guard let page = self.buildPage(item: item) else {
            owsFailDebug("unexpectedly unable to build new page")
            return
        }

        page.loadViewIfNeeded()

        self.setViewControllers([page], direction: direction, animated: isAnimated, completion: nil)
        updateMediaRail()
    }

    func updateMediaRail() {
        guard let currentItem = self.currentItem else {
            owsFailDebug("currentItem was unexpectedly nil")
            return
        }

        let cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView = { [weak self] railItem in
            switch railItem {
            case is AddMoreRailItem:
                return GalleryRailCellView()
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
                                           animated: false)
    }

    var attachmentApprovalItemCollection: AttachmentApprovalItemCollection!

    var attachmentApprovalItems: [AttachmentApprovalItem] {
        return attachmentApprovalItemCollection.attachmentApprovalItems
    }

    var attachments: [SignalAttachment] {
        return attachmentApprovalItems.map { (attachmentApprovalItem) in
            autoreleasepool {
                return self.processedAttachment(forAttachmentItem: attachmentApprovalItem)
            }
        }
    }

    // For any attachments edited with the image editor, returns a
    // new SignalAttachment that reflects those changes.  Otherwise,
    // returns the original attachment.
    //
    // If any errors occurs in the export process, we fail over to
    // sending the original attachment.  This seems better than trying
    // to involve the user in resolving the issue.
    func processedAttachment(forAttachmentItem attachmentApprovalItem: AttachmentApprovalItem) -> SignalAttachment {
        guard let imageEditorModel = attachmentApprovalItem.imageEditorModel else {
            // Image was not edited.
            return attachmentApprovalItem.attachment
        }
        guard imageEditorModel.isDirty() else {
            // Image editor has no changes.
            return attachmentApprovalItem.attachment
        }
        guard let dstImage = imageEditorModel.renderOutput() else {
            owsFailDebug("Could not render for output.")
            return attachmentApprovalItem.attachment
        }
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

        let dstAttachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataUTI, imageQuality: .original)
        if let attachmentError = dstAttachment.error {
            owsFailDebug("Could not prepare attachment for output: \(attachmentError).")
            return attachmentApprovalItem.attachment
        }
        // Preserve caption text.
        dstAttachment.captionText = attachmentApprovalItem.captionText
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

    // MARK: - Event Handlers

    @objc
    func didTapTouchInterceptorView(gesture: UITapGestureRecognizer) {
        Logger.info("")

        isEditingCaptions = false
    }

    private func cancelPressed() {
        self.approvalDelegate?.attachmentApprovalDidCancel(self)
    }

    @objc func didTapCaption(sender: UIButton) {
        Logger.verbose("")

        isEditingCaptions = true
    }

    @objc func didTapCaptionDone(sender: UIButton) {
        Logger.verbose("")

        isEditingCaptions = false
    }

    public func didTapSave() {
            let errorText = NSLocalizedString("ATTACHMENT_APPROVAL_FAILED_TO_SAVE",
                                              comment: "alert text when Signal was unable to save a copy of the attachment to the system photo library")
            do {
                let saveableAsset: SaveableAsset = try SaveableAsset(attachmentApprovalItem: self.currentItem)

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
                    }) { didSucceed, error in
                        DispatchQueue.main.async {
                            if didSucceed {
                                let toastController = ToastController(text: NSLocalizedString("ATTACHMENT_APPROVAL_MEDIA_DID_SAVE",
                                                                                              comment: "toast alert shown after user taps the 'save' button"))
                                let inset = self.bottomToolView.height() + 16
                                toastController.presentToastView(fromBottomOfView: self.view, inset: inset)
                            } else {
                                owsFailDebug("error: \(String(describing: error))")
                                OWSAlerts.showErrorAlert(message: errorText)
                            }
                        }
                    }
                }
            } catch {
                owsFailDebug("error: \(error)")
                OWSAlerts.showErrorAlert(message: errorText)
            }
    }
}

// MARK: -

extension AttachmentApprovalViewController: AttachmentTextToolbarDelegate {
    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        currentPageViewController.setAttachmentViewScale(.compact, animated: true)
    }

    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        currentPageViewController.setAttachmentViewScale(.fullsize, animated: true)
    }

    func attachmentTextToolbarDidTapSend(_ attachmentTextToolbar: AttachmentTextToolbar) {
        // Toolbar flickers in and out if there are errors
        // and remains visible momentarily after share extension is dismissed.
        // It's easiest to just hide it at this point since we're done with it.
        currentPageViewController.shouldAllowAttachmentViewResizing = false
        updateContents(isApproved: true)

        // Generate the attachments once, so that any changes we
        // make below are reflected afterwards.
        let attachments = self.attachments

        if options.contains(.canToggleViewOnce),
            preferences.isViewOnceMessagesEnabled() {
            for attachment in attachments {
                attachment.isViewOnceAttachment = true
            }
            assert(attachments.count <= 1)
        }

        approvalDelegate?.attachmentApproval(self, didApproveAttachments: attachments, messageText: attachmentTextToolbar.messageText)
    }

    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar) {
        approvalDelegate?.attachmentApproval(self, didChangeMessageText: attachmentTextToolbar.messageText)
    }

    func attachmentTextToolbarDidViewOnce(_ attachmentTextToolbar: AttachmentTextToolbar) {
        updateContents(isApproved: false)
    }
}

// MARK: -

extension AttachmentApprovalViewController: AttachmentPrepViewControllerDelegate {
    func prepViewControllerUpdateNavigationBar() {
        updateNavigationBar()
    }

    func prepViewControllerUpdateControls() {
        updateInputAccessory(isApproved: false)
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
            self.approvalDelegate?.attachmentApprovalDidTapAddMore?(self)
            return
        }

        guard let targetItem = imageRailItem as? AttachmentApprovalItem else {
            owsFailDebug("unexpected imageRailItem: \(imageRailItem)")
            return
        }

        guard let currentIndex = attachmentApprovalItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return
        }

        guard let targetIndex = attachmentApprovalItems.firstIndex(of: targetItem) else {
            owsFailDebug("targetIndex was unexpectedly nil")
            return
        }

        let direction: UIPageViewController.NavigationDirection = currentIndex < targetIndex ? .forward : .reverse

        self.setCurrentItem(targetItem, direction: direction, animated: true)
    }
}

// MARK: -

enum KeyboardScenario {
    case hidden, editingMessage, editingCaption
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

extension AttachmentApprovalViewController: AttachmentApprovalInputAccessoryViewDelegate {
    public func attachmentApprovalInputUpdateMediaRail() {
        updateMediaRail()
    }

    public func attachmentApprovalInputStartEditingCaptions() {
        isEditingCaptions = true
    }

    public func attachmentApprovalInputStopEditingCaptions() {
        isEditingCaptions = false
    }
}

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
                throw OWSAssertionError("imageUrl was unexpetedly nil")
            }

            self = .imageUrl(imageUrl)
        } else if attachment.isValidVideo {
            guard let videoUrl = attachment.dataUrl else {
                throw OWSAssertionError("videoUrl was unexpetedly nil")
            }

            self = .videoUrl(videoUrl)
        } else {
            throw OWSAssertionError("unsaveable media")
        }
    }
}
