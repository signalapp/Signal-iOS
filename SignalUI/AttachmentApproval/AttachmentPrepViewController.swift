//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit

protocol AttachmentPrepViewControllerDelegate: AnyObject {

    func attachmentPrepViewControllerDidRequestUpdateControlsVisibility(
        _ viewController: AttachmentPrepViewController,
        completion: ((Bool) -> Void)?,
    )
}

protocol AttachmentPrepContentView: UIView {
    func setHasRoundedCorners(_ hasRoundedCorners: Bool, animationDuration: TimeInterval)
}

public class AttachmentPrepViewController: OWSViewController, UIScrollViewDelegate {

    // MARK: - Properties

    weak var prepDelegate: AttachmentPrepViewControllerDelegate?

    let attachmentApprovalItem: AttachmentApprovalItem
    var attachment: PreviewableAttachment {
        return attachmentApprovalItem.attachment
    }

    let isZoomable: Bool

    var toolbarSupplementaryView: UIView? { nil }

    // MARK: - Initializers

    class func viewController(
        for attachmentApprovalItem: AttachmentApprovalItem,
        stickerSheetDelegate: StickerPickerSheetDelegate?,
    ) -> AttachmentPrepViewController? {
        switch attachmentApprovalItem.type {
        case .image:
            let viewController = ImageAttachmentPrepViewController(attachmentApprovalItem: attachmentApprovalItem)
            viewController?.stickerSheetDelegate = stickerSheetDelegate
            return viewController
        case .video: return VideoAttachmentPrepViewController(attachmentApprovalItem: attachmentApprovalItem)
        case .generic: return AttachmentPrepViewController(attachmentApprovalItem: attachmentApprovalItem)
        }
    }

    init?(attachmentApprovalItem: AttachmentApprovalItem) {
        self.attachmentApprovalItem = attachmentApprovalItem
        // No zoom for audio or generic attachments.
        let attachment = attachmentApprovalItem.attachment
        self.isZoomable = attachment.isImage || attachment.isVideo

        super.init()
    }

    // MARK: - Customization Points for Subclasses

    private lazy var genericContentView = MediaMessageView(attachment: attachment)

    var contentView: UIView {
        return genericContentView
    }

    func prepareContentView() { }

    func prepareToMoveOffscreen() {
        updateScrollViewTransform(keyboardHeight: 0)
    }

    private var isMediaToolViewControllerPresented = false

    public var shouldHideControls: Bool {
        return isMediaToolViewControllerPresented
    }

    public var canSaveMedia: Bool {
        return attachmentApprovalItem.canSave
    }

    // MARK: UIViewController

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.mediaBackground

        let contentView = contentView
        prepareContentView()

        if isZoomable {
            // Zoomable scroll view.
            let scrollView = UIScrollView()
            scrollView.delegate = self
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            // Panning should stop pretty soon after the user stops scrolling
            scrollView.decelerationRate = .fast
            // We control the viewport ourselves by centering `contentView`.
            scrollView.contentInsetAdjustmentBehavior = .always
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)
            scrollView.addSubview(contentView)
            NSLayoutConstraint.activate([
                scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
                scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            self.scrollView = scrollView
        } else {
            // Simple subview constrained to layout margins.
            contentView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(contentView)
            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
                contentView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
            ])
        }
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        isMediaToolViewControllerPresented = false
        prepDelegate?.attachmentPrepViewControllerDidRequestUpdateControlsVisibility(self, completion: nil)
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if isZoomable {
            configureScrollViewContentSizeAndZoom()
            centerContent()
        }
    }

    // MARK: Layout

    static let contentInsets = UIEdgeInsets(
        hMargin: OWSTableViewController2.defaultHOuterMargin,
        vMargin: 16, // top and bottom bars each have additional 8dp of padding
    )

    private var needsInitialZoom = true

    private var scrollView: UIScrollView?

    private var zoomAnimationCompletionBlock: (() -> Void)?

    func zoomOut(animated: Bool, completion: (() -> Void)? = nil) {
        guard isZoomable, let scrollView, scrollView.zoomScale != scrollView.minimumZoomScale else {
            zoomAnimationCompletionBlock = nil
            completion?()
            return
        }

        zoomAnimationCompletionBlock = completion
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
    }

    private func configureScrollViewContentSizeAndZoom() {
        guard let scrollView, scrollView.transform == .identity else { return }

        // This defines scroll edges for zoomed in content.
        // Additional safe area insets would be set by AttachmentApprovalViewController
        // to make space for top and bottom controls.
        let scrollViewBounds = scrollView.bounds.inset(by: view.safeAreaInsets)
        guard scrollViewBounds.size.isNonEmpty else { return }

        // This is the area for the content at default, zoomed out state.
        // There are standard margins on vertical sides and 24 dp padding above and below.
        let maxDefaultContentSize = scrollViewBounds.inset(by: Self.contentInsets).size

        // Get intrinsic content size and scale it down to fit the screen.
        // That scaled down content size will be scroll view's content size at minimum zoom - 1.
        // We need to do it this way because there might be rounded corners
        // on the content view that must apply to default content size.
        var fullContentSize = contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        if fullContentSize.isNonEmpty == false {
            Logger.warn("Intrinsic content size is unknown.")
            fullContentSize = maxDefaultContentSize
        }

        let scaleX = maxDefaultContentSize.width / fullContentSize.width
        let scaleY = maxDefaultContentSize.height / fullContentSize.height
        let scale = min(1, min(scaleX, scaleY))

        // Using `contentView.systemLayoutSizeFitting(viewPort.size)` might not always work,
        // depending on internal constraints / sizing logic of the content view.
        let contentSize = fullContentSize * scale

        if scrollView.contentSize != contentSize {
            // Origin doesn't matter here because we'll re-center content anyway.
            contentView.frame = CGRect(origin: .zero, size: contentSize)
            needsInitialZoom = true
        }

        let minZoomScale: CGFloat = 1
        let maxZoomScale = max(1, 1 / scale)

        // This allows to keep content at min zoom level after rotation.
        let wasAtMinimum = abs(scrollView.zoomScale - scrollView.minimumZoomScale) < 0.0001

        scrollView.minimumZoomScale = minZoomScale
        scrollView.maximumZoomScale = maxZoomScale

        if needsInitialZoom || wasAtMinimum {
            scrollView.zoomScale = minZoomScale
            needsInitialZoom = false
        } else {
            scrollView.zoomScale = scrollView.zoomScale.clamp(minZoomScale, maxZoomScale)
        }
    }

    private func centerContent() {
        guard let scrollView, scrollView.transform == .identity else { return }

        // Content smaller than these bounds would be centered within this area.
        let scrollViewBounds = scrollView.bounds.inset(by: scrollView.safeAreaInsets)
        guard scrollViewBounds.size.isNonEmpty else { return }

        // Post-transform size, derived rather than read off `frame`.
        let scaledContentSize = contentView.bounds.size * scrollView.zoomScale

        // If content view's frame is smaller than the scroll view's viewport
        // we need to adjust the center by half the size difference, centering the content view.
        // Otherwise keep the content view's origin pinned to (0, 0).
        let centerOffsetX = max(0, (scrollViewBounds.width - scaledContentSize.width) / 2)
        let centerOffsetY = max(0, (scrollViewBounds.height - scaledContentSize.height) / 2)
        contentView.center = CGPoint(
            x: scrollView.contentSize.width / 2 + centerOffsetX,
            y: scrollView.contentSize.height / 2 + centerOffsetY,
        )
    }

    func updateScrollViewTransform(keyboardHeight: CGFloat) {
        let viewToScale = scrollView ?? contentView

        guard keyboardHeight > 0 else {
            viewToScale.transform = .identity
            return
        }

        let adjustedHeightChange = max(0, keyboardHeight - view.safeAreaInsets.bottom)
        viewToScale.transform = .translate(.init(x: 0, y: -adjustedHeightChange / 2))
    }

    // MARK: Tools

    private func _presentMediaTool(viewController: UIViewController) {
        if let presentedViewController {
            owsAssertDebug(false, "Already has presented view controller. [\(presentedViewController)]")
            presentedViewController.dismiss(animated: false) { [weak self] in
                self?._presentMediaTool(viewController: viewController)
            }
            return
        }

        zoomOut(animated: true) { [weak self] in
            // Cover the current context. This ensures that we stay within our
            // containing frame in the share extension.
            viewController.modalPresentationStyle = .currentContext
            self?.present(viewController, animated: false)
        }
    }

    final func presentMediaTool(viewController: UIViewController) {
        if let prepDelegate {
            isMediaToolViewControllerPresented = true
            prepDelegate.attachmentPrepViewControllerDidRequestUpdateControlsVisibility(self) { _ in
                self._presentMediaTool(viewController: viewController)
            }
        } else {
            self._presentMediaTool(viewController: viewController)
        }
    }

    func activatePenTool() { }

    func activateCropTool() { }

    // MARK: - UIScrollViewDelegate

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        guard isZoomable else {
            return nil
        }
        return contentView
    }

    // Keep the media view centered within the scroll view as you zoom
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        if let attachmentPrepContentView = contentView as? AttachmentPrepContentView {
            attachmentPrepContentView.setHasRoundedCorners(
                (scrollView.zoomScale - scrollView.minimumZoomScale) < 0.1,
                animationDuration: 0.1,
            )
        }
    }

    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if let zoomAnimationCompletionBlock {
            zoomAnimationCompletionBlock()
            self.zoomAnimationCompletionBlock = nil
        }
    }
}
