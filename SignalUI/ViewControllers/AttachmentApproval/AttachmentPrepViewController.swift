//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
import SignalMessaging
import UIKit

protocol AttachmentPrepViewControllerDelegate: AnyObject {

    func attachmentPrepViewControllerDidRequestUpdateControlsVisibility(_ viewController: AttachmentPrepViewController,
                                                                        completion: ((Bool) -> Void)?)
}

// MARK: -

public class AttachmentPrepViewController: OWSViewController {

    // MARK: - Properties

    weak var prepDelegate: AttachmentPrepViewControllerDelegate?

    let attachmentApprovalItem: AttachmentApprovalItem
    var attachment: SignalAttachment {
        return attachmentApprovalItem.attachment
    }

    var toolbarSupplementaryView: UIView? { nil }

    // MARK: - Initializers

    class func viewController(for attachmentApprovalItem: AttachmentApprovalItem) -> AttachmentPrepViewController? {
        switch attachmentApprovalItem.type {
        case .image: return ImageAttachmentPrepViewController(attachmentApprovalItem: attachmentApprovalItem)
        case .video: return VideoAttachmentPrepViewController(attachmentApprovalItem: attachmentApprovalItem)
        case .generic: return AttachmentPrepViewController(attachmentApprovalItem: attachmentApprovalItem)
        }
    }

    required init?(attachmentApprovalItem: AttachmentApprovalItem) {
        guard !attachmentApprovalItem.attachment.hasError else {
            return nil
        }
        self.attachmentApprovalItem = attachmentApprovalItem
        super.init()
    }

    // MARK: - Customization Points for Subclasses

    private lazy var genericContentView = MediaMessageView(attachment: attachment)

    var contentView: UIView {
        return genericContentView
    }

    func prepareContentView() { }

    func prepareToMoveOffscreen() { }

    private var isMediaToolViewControllerPresented = false

    public var shouldHideControls: Bool {
        return isMediaToolViewControllerPresented
    }

    public var canSaveMedia: Bool {
        return attachmentApprovalItem.canSave
    }

    /**
     * Subclasses can override this property if they want some other metric to be used when calculating
     * bottom inset for `contentView.contentLayoutGuide`.
     * Currently this is only used by `ImageAttachmentPrepViewController` to ensure
     * that image doesn't move when switching to / from edit mode.
     */
    var mediaEditingToolbarHeight: CGFloat? { nil }

    // MARK: UIViewController

    override public func viewDidLoad() {
        view.backgroundColor = .ows_black

        // Zoomable scroll view.
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints([ scrollViewLeading, scrollViewTop, scrollViewTrailing, scrollViewBottom ])

        // Create full screen container view so the scrollView
        // can compute an appropriate content size in which to center
        // our media view.
        let containerView = UIView.container()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(containerView)
        scrollView.addConstraints([
            containerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            containerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            containerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        ])
        containerView.autoMatch(.height, to: .height, of: scrollView)
        containerView.autoMatch(.width, to: .width, of: scrollView)

        let contentView = contentView
        contentView.frame = containerView.bounds
        prepareContentView()
        containerView.addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges()

        updateMinZoomScaleForSize(view.bounds.size)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Avoid unwanted animations when review screen appears.
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        isMediaToolViewControllerPresented = false
        prepDelegate?.attachmentPrepViewControllerDidRequestUpdateControlsVisibility(self, completion: nil)
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.updateMinZoomScaleForSize(size)
        }
    }

    // MARK: Layout

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        // Panning should stop pretty soon after the user stops scrolling
        scrollView.decelerationRate = .fast
        // We want scroll view content up and behind the system status bar content
        // but we want other content (e.g. bar buttons) to respect the top layout guide.
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()

    private lazy var scrollViewLeading = scrollView.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: contentLayoutMargins.leading
    )
    private lazy var scrollViewTop = scrollView.topAnchor.constraint(
        equalTo: view.topAnchor,
        constant: contentLayoutMargins.top
    )
    private lazy var scrollViewTrailing = scrollView.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -contentLayoutMargins.trailing
    )
    private lazy var scrollViewBottom = scrollView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor,
        constant: -contentLayoutMargins.bottom
    )
    var contentLayoutMargins: UIEdgeInsets = .zero {
        didSet {
            guard oldValue != contentLayoutMargins else { return }
            scrollViewLeading.constant = contentLayoutMargins.leading
            scrollViewTop.constant = contentLayoutMargins.top
            scrollViewTrailing.constant = -contentLayoutMargins.trailing
            scrollViewBottom.constant = -contentLayoutMargins.bottom
        }
    }

    private var zoomAnimationCompletionBlock: (() -> Void)?

    func zoomOut(animated: Bool, completion: (() -> Void)? = nil) {
        guard scrollView.zoomScale != scrollView.minimumZoomScale else {
            zoomAnimationCompletionBlock = nil
            completion?()
            return
        }

        zoomAnimationCompletionBlock = completion
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
    }

    // Implicitly animatable.
    var keyboardHeight: CGFloat = 0 {
        didSet {
            updateScrollViewTransformForKeyboardHeight()
        }
    }

    private func updateScrollViewTransformForKeyboardHeight() {
        guard keyboardHeight > 0 else {
            scrollView.transform = .identity
            return
        }

        let contentViewSize = contentView.bounds.size
        let scaledContentViewSize = contentView.bounds.inset(by: .init(margin: 20)).size
        let scale = min(scaledContentViewSize.width / contentViewSize.width,
                        scaledContentViewSize.height / contentViewSize.height)

        let offsetY = 0.5 * max(0, keyboardHeight - contentLayoutMargins.bottom)

        scrollView.transform = .scale(scale).translate(.init(x: 0, y: -offsetY))
    }

    private func presentFullScreen(viewController: UIViewController) {
        if let presentedViewController = presentedViewController {
            owsAssertDebug(false, "Already has presented view controller. [\(presentedViewController)]")
            presentedViewController.dismiss(animated: false)
        }

        viewController.modalPresentationStyle = .fullScreen
        zoomOut(animated: true) { [weak self] in
            self?.presentFullScreen(viewController, animated: false)
        }
    }

    final func presentMediaTool(viewController: UIViewController) {
        if let prepDelegate = prepDelegate {
            isMediaToolViewControllerPresented = true
            prepDelegate.attachmentPrepViewControllerDidRequestUpdateControlsVisibility(self) { _ in
                self.presentFullScreen(viewController: viewController)
            }
        } else {
            self.presentFullScreen(viewController: viewController)
        }
    }

    func activatePenTool() { }

    func activateCropTool() { }
}

extension AttachmentPrepViewController: UIScrollViewDelegate {

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        guard isZoomable else {
            return nil
        }
        return contentView
    }

    private func updateMinZoomScaleForSize(_ size: CGSize) {
        // Ensure bounds have been computed
        contentView.layoutIfNeeded()
        guard contentView.bounds.width > 0, contentView.bounds.height > 0 else {
            Logger.warn("bad bounds")
            return
        }

        let widthScale = size.width / contentView.bounds.width
        let heightScale = size.height / contentView.bounds.height
        let minScale = min(widthScale, heightScale)
        scrollView.maximumZoomScale = minScale * 5.0
        scrollView.minimumZoomScale = minScale
        scrollView.zoomScale = minScale
    }

    // Keep the media view centered within the scroll view as you zoom
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // The scroll view has zoomed, so you need to re-center the contents
        let scrollViewSize = scrollView.frame.size

        // First assume that mediaMessageView center coincides with the contents center
        // This is correct when the mediaMessageView is bigger than scrollView due to zoom
        var contentCenter = CGPoint(x: (scrollView.contentSize.width / 2), y: (scrollView.contentSize.height / 2))

        // if mediaMessageView is smaller than the scrollView visible size - fix the content center accordingly
        if scrollView.contentSize.width < scrollViewSize.width {
            contentCenter.x = 0.5 * scrollViewSize.width
        }
        if scrollView.contentSize.height < scrollViewSize.height {
            contentCenter.y = 0.5 * scrollViewSize.height
        }

        contentView.center = contentCenter
    }

    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if let zoomAnimationCompletionBlock {
            zoomAnimationCompletionBlock()
            self.zoomAnimationCompletionBlock = nil
        }
    }

    private var isZoomable: Bool {
        // No zoom for audio or generic attachments.
        return attachment.isImage || attachment.isVideo
    }
}
