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
    // We sometimes shrink the attachment view so that it remains somewhat visible
    // when the keyboard is presented.
    public enum AttachmentViewScale {
        case fullsize, compact
    }

    // MARK: - Properties

    weak var prepDelegate: AttachmentPrepViewControllerDelegate?

    let attachmentApprovalItem: AttachmentApprovalItem
    var attachment: SignalAttachment {
        return attachmentApprovalItem.attachment
    }

    var toolbarSupplementaryView: UIView? { nil }

    private(set) var scrollView: UIScrollView!
    private(set) var contentContainer: UIView!

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

    var contentView: AttachmentPrepContentView {
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

    // MARK: - View Lifecycle

    override public func loadView() {
        view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .ows_black

        // Anything that should be shrunk when user pops keyboard lives in the contentContainer.
        contentContainer = UIView(frame: view.bounds)
        view.addSubview(contentContainer)
        contentContainer.autoPinEdgesToSuperviewEdges()

        // Scroll View - used to zoom/pan on images and video
        scrollView = UIScrollView(frame: contentContainer.bounds)
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        // Panning should stop pretty soon after the user stops scrolling
        scrollView.decelerationRate = .fast
        // We want scroll view content up and behind the system status bar content
        // but we want other content (e.g. bar buttons) to respect the top layout guide.
        scrollView.contentInsetAdjustmentBehavior = .never
        contentContainer.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        // Create full screen container view so the scrollView
        // can compute an appropriate content size in which to center
        // our media view.
        let containerView = UIView.container()
        containerView.frame = view.bounds
        scrollView.addSubview(containerView)
        containerView.autoPinEdgesToSuperviewEdges()
        containerView.autoMatch(.height, to: .height, of: view)
        containerView.autoMatch(.width, to: .width, of: view)

        let contentView = contentView
        contentView.frame = containerView.bounds
        prepareContentView()
        containerView.addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges()
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
            self.ensureAttachmentViewScale(animated: false)
        }
    }

    // MARK: - Helpers

    func zoomOut(animated: Bool) {
        if scrollView.zoomScale != scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        }
    }

    // When the keyboard is popped, it can obscure the attachment view.
    // so we sometimes allow resizing the attachment.
    var shouldAllowAttachmentViewResizing: Bool = true

    var attachmentViewScale: AttachmentViewScale = .fullsize
    public func setAttachmentViewScale(_ attachmentViewScale: AttachmentViewScale, animated: Bool) {
        self.attachmentViewScale = attachmentViewScale
        ensureAttachmentViewScale(animated: animated)
    }

    func ensureAttachmentViewScale(animated: Bool) {
        let animationDuration = animated ? 0.2 : 0
        guard shouldAllowAttachmentViewResizing else {
            if contentContainer.transform != CGAffineTransform.identity {
                UIView.animate(withDuration: animationDuration) {
                    self.contentContainer.transform = CGAffineTransform.identity
                }
            }
            return
        }

        switch attachmentViewScale {
        case .fullsize:
            guard contentContainer.transform != .identity else {
                return
            }
            UIView.animate(withDuration: animationDuration) {
                self.contentContainer.transform = CGAffineTransform.identity
            }
        case .compact:
            guard contentContainer.transform == .identity else {
                return
            }
            UIView.animate(withDuration: animationDuration) {
                let kScaleFactor: CGFloat = 0.7
                let scale = CGAffineTransform(scaleX: kScaleFactor, y: kScaleFactor)

                let originalHeight = self.scrollView.bounds.size.height

                // Position the new scaled item to be centered with respect
                // to it's new size.
                let heightDelta = originalHeight * (1 - kScaleFactor)
                let translate = CGAffineTransform(translationX: 0, y: -heightDelta / 2)

                self.contentContainer.transform = scale.concatenating(translate)
            }
        }
    }

    private func presentFullScreen(viewController: UIViewController) {
        if let presentedViewController = presentedViewController {
            owsAssertDebug(false, "Already has presented view controller. [\(presentedViewController)]")
            presentedViewController.dismiss(animated: false)
        }

        viewController.modalPresentationStyle = .fullScreen
        presentFullScreen(viewController, animated: false)
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
        let scrollViewSize = visibleSize(ofScrollView: scrollView)
        let scrollViewCenter = center(ofScrollView: scrollView)

        // First assume that mediaMessageView center coincides with the contents center
        // This is correct when the mediaMessageView is bigger than scrollView due to zoom
        var contentCenter = CGPoint(x: (scrollView.contentSize.width / 2), y: (scrollView.contentSize.height / 2))

        // if mediaMessageView is smaller than the scrollView visible size - fix the content center accordingly
        if scrollView.contentSize.width < scrollViewSize.width {
            contentCenter.x = scrollViewCenter.x
        }

        if scrollView.contentSize.height < scrollViewSize.height {
            contentCenter.y = scrollViewCenter.y
        }

        contentView.center = contentCenter
    }

    private var isZoomable: Bool {
        // No zoom for audio or generic attachments.
        return attachment.isImage || attachment.isVideo
    }

    // return the scroll view center
    private func center(ofScrollView scrollView: UIScrollView) -> CGPoint {
        let size = visibleSize(ofScrollView: scrollView)
        return CGPoint(x: (size.width / 2), y: (size.height / 2))
    }

    // Return scrollview size without the area overlapping with tab and nav bar.
    private func visibleSize(ofScrollView scrollView: UIScrollView) -> CGSize {
        let contentInset = scrollView.contentInset
        let scrollViewSize = scrollView.bounds.standardized.size
        let width = scrollViewSize.width - (contentInset.left + contentInset.right)
        let height = scrollViewSize.height - (contentInset.top + contentInset.bottom)
        return CGSize(width: width, height: height)
    }
}
