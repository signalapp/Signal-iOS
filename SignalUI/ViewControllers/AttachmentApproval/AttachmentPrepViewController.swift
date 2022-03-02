//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import SignalMessaging

protocol AttachmentPrepViewControllerDelegate: AnyObject {
    func prepViewControllerUpdateNavigationBar()

    func prepViewControllerUpdateControls()

    var prepViewControllerShouldIgnoreTapGesture: Bool { get }
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

    private(set) var scrollView: UIScrollView!
    private(set) var contentContainer: UIView!

    private var imageEditorView: ImageEditorView?
    private var imageEditorViewConstraintsPortrait: [NSLayoutConstraint]?
    private var imageEditorViewConstraintsLandscape: [NSLayoutConstraint]?

    private var videoEditorView: VideoEditorView?
    private var videoEditorViewConstraintsPortrait: [NSLayoutConstraint]?
    private var videoEditorViewConstraintsLandscape: [NSLayoutConstraint]?

    private var mediaMessageView: MediaMessageView?

    public var shouldHideControls: Bool {
        if let imageEditorView = imageEditorView {
            return imageEditorView.shouldHideControls
        }
        if let videoEditorView = videoEditorView {
            return videoEditorView.shouldHideControls
        }
        return false
    }

    // MARK: - Initializers

    init(attachmentApprovalItem: AttachmentApprovalItem) {
        self.attachmentApprovalItem = attachmentApprovalItem
        super.init()
        assert(!attachment.hasError)
    }

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
        contentContainer.addSubview(scrollView)

        // Panning should stop pretty soon after the user stops scrolling
        scrollView.decelerationRate = UIScrollView.DecelerationRate.fast

        // We want scroll view content up and behind the system status bar content
        // but we want other content (e.g. bar buttons) to respect the top layout guide.
        scrollView.contentInsetAdjustmentBehavior = .never

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

        let contentMarginTop = UIDevice.current.hasIPhoneXNotch ? CurrentAppContext().statusBarHeight : 0

        if let imageEditorModel = attachmentApprovalItem.imageEditorModel {

            let imageEditorView = ImageEditorView(model: imageEditorModel, delegate: self)
            imageEditorView.frame = view.bounds
            imageEditorView.configureSubviews()
            imageEditorView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(imageEditorView)

            imageEditorViewConstraintsPortrait = [
                imageEditorView.heightAnchor.constraint(equalTo: imageEditorView.widthAnchor, multiplier: 16/9),
                imageEditorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                imageEditorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                imageEditorView.topAnchor.constraint(equalTo: view.topAnchor, constant: contentMarginTop) ]
            imageEditorViewConstraintsLandscape = [
                imageEditorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                imageEditorView.topAnchor.constraint(equalTo: view.topAnchor),
                imageEditorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                imageEditorView.bottomAnchor.constraint(equalTo: view.bottomAnchor) ]

            self.imageEditorView = imageEditorView

            imageEditorUpdateNavigationBar()
        } else if let videoEditorModel = attachmentApprovalItem.videoEditorModel {

            let videoEditorView = VideoEditorView(model: videoEditorModel,
                                                  attachmentApprovalItem: attachmentApprovalItem,
                                                  delegate: self)
            videoEditorView.frame = view.bounds
            videoEditorView.configureSubviews()
            videoEditorView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(videoEditorView)

            videoEditorViewConstraintsPortrait = [
                videoEditorView.heightAnchor.constraint(equalTo: videoEditorView.widthAnchor, multiplier: 16/9),
                videoEditorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                videoEditorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                videoEditorView.topAnchor.constraint(equalTo: view.topAnchor, constant: contentMarginTop) ]
            videoEditorViewConstraintsLandscape = [
                videoEditorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                videoEditorView.topAnchor.constraint(equalTo: view.topAnchor),
                videoEditorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                videoEditorView.bottomAnchor.constraint(equalTo: view.bottomAnchor) ]

            self.videoEditorView = videoEditorView

            videoEditorUpdateNavigationBar()
        } else {
            let mediaMessageView = MediaMessageView(attachment: attachment, mode: .attachmentApproval)
            containerView.addSubview(mediaMessageView)
            mediaMessageView.autoPinEdgesToSuperviewEdges()
            self.mediaMessageView = mediaMessageView
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        updateLayoutConstraints()
    }

    override public func viewWillAppear(_ animated: Bool) {
        Logger.debug("")

        super.viewWillAppear(animated)

        prepDelegate?.prepViewControllerUpdateNavigationBar()
        prepDelegate?.prepViewControllerUpdateControls()

        showBlurTooltipIfNecessary()
    }

    override public func viewDidAppear(_ animated: Bool) {
        Logger.debug("")

        super.viewDidAppear(animated)

        prepDelegate?.prepViewControllerUpdateNavigationBar()
        prepDelegate?.prepViewControllerUpdateControls()
    }

    override public func viewWillLayoutSubviews() {
        Logger.debug("")
        super.viewWillLayoutSubviews()

        // e.g. if flipping to/from landscape
        updateMinZoomScaleForSize(view.bounds.size)

        ensureAttachmentViewScale(animated: false)

        positionBlurTooltip()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass {
            updateLayoutConstraints()
        }
    }

    // MARK: - Navigation Bar

    public func navigationBarItems() -> [UIView] {
        if let imageEditorView = imageEditorView {
            return imageEditorView.navigationBarItems()
        }
        if let videoEditorView = videoEditorView {
            return videoEditorView.navigationBarItems()
        }
        return []
    }

    public var hasCustomSaveButton: Bool {
        return videoEditorView != nil
    }

    // MARK: - Helpers

    var isZoomable: Bool {
        return attachment.isImage || attachment.isVideo
    }

    func zoomOut(animated: Bool) {
        if self.scrollView.zoomScale != self.scrollView.minimumZoomScale {
            self.scrollView.setZoomScale(self.scrollView.minimumZoomScale, animated: animated)
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
            if self.contentContainer.transform != CGAffineTransform.identity {
                UIView.animate(withDuration: animationDuration) {
                    self.contentContainer.transform = CGAffineTransform.identity
                }
            }
            return
        }

        switch attachmentViewScale {
        case .fullsize:
            guard self.contentContainer.transform != .identity else {
                return
            }
            UIView.animate(withDuration: animationDuration) {
                self.contentContainer.transform = CGAffineTransform.identity
            }
        case .compact:
            guard self.contentContainer.transform == .identity else {
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

    private func updateLayoutConstraints() {
        let isPortraitLayout = traitCollection.horizontalSizeClass == .compact

        var constraintsToRemove: [NSLayoutConstraint]?
        var constraintsToAdd: [NSLayoutConstraint]?

        if imageEditorView != nil {
            if isPortraitLayout {
                constraintsToRemove = imageEditorViewConstraintsLandscape
                constraintsToAdd = imageEditorViewConstraintsPortrait
            } else {
                constraintsToRemove = imageEditorViewConstraintsPortrait
                constraintsToAdd = imageEditorViewConstraintsLandscape
            }
        } else if videoEditorView != nil {
            if isPortraitLayout {
                constraintsToRemove = videoEditorViewConstraintsLandscape
                constraintsToAdd = videoEditorViewConstraintsPortrait
            } else {
                constraintsToRemove = videoEditorViewConstraintsPortrait
                constraintsToAdd = videoEditorViewConstraintsLandscape
            }
        }
        if let constraintsToRemove = constraintsToRemove {
            view.removeConstraints(constraintsToRemove)
        }
        if let constraintsToAdd = constraintsToAdd {
            view.addConstraints(constraintsToAdd)
        }
    }

    // MARK: - Tooltip

    private var shouldShowBlurTooltip: Bool {
        guard imageEditorView != nil else { return false }

        guard !preferences.wasBlurTooltipShown() else {
            return false
        }
        return true
    }

    private var blurTooltip: UIView?
    private var blurTooltipTailReferenceView: UIView?

    // Show the tooltip if a) it should be shown b) isn't already showing.
    private func showBlurTooltipIfNecessary() {
        guard shouldShowBlurTooltip else { return }
        guard blurTooltip == nil else { return }

        let tailReferenceView = UIView()
        tailReferenceView.isUserInteractionEnabled = false
        view.addSubview(tailReferenceView)
        blurTooltipTailReferenceView = tailReferenceView

        let tooltip = BlurTooltip.present(
            fromView: view,
            widthReferenceView: view,
            tailReferenceView: tailReferenceView
        ) { [weak self] in
            self?.removeBlurTooltip()
            self?.imageEditorView?.didTapBlur()
        }
        blurTooltip = tooltip

        DispatchQueue.global().async {
            self.preferences.setWasBlurTooltipShown()

            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5) { [weak self] in
                self?.removeBlurTooltip()
            }
        }
    }

    private func positionBlurTooltip() {
        guard let blurTooltipTailReferenceView = blurTooltipTailReferenceView else { return }
        guard let imageEditorView = imageEditorView else { return }

        blurTooltipTailReferenceView.frame = view.convert(imageEditorView.blurButton.frame, from: imageEditorView.blurButton.superview)
    }

    private func removeBlurTooltip() {
        blurTooltip?.removeFromSuperview()
        blurTooltip = nil
        blurTooltipTailReferenceView?.removeFromSuperview()
        blurTooltipTailReferenceView = nil
    }
}

// MARK: -

extension AttachmentPrepViewController: UIScrollViewDelegate {

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        if isZoomable {
            return mediaMessageView
        } else {
            // don't zoom for audio or generic attachments.
            return nil
        }
    }

    fileprivate func updateMinZoomScaleForSize(_ size: CGSize) {
        Logger.debug("")

        guard let mediaMessageView = mediaMessageView else {
            return
        }

        // Ensure bounds have been computed
        mediaMessageView.layoutIfNeeded()
        guard mediaMessageView.bounds.width > 0, mediaMessageView.bounds.height > 0 else {
            Logger.warn("bad bounds")
            return
        }

        let widthScale = size.width / mediaMessageView.bounds.width
        let heightScale = size.height / mediaMessageView.bounds.height
        let minScale = min(widthScale, heightScale)
        scrollView.maximumZoomScale = minScale * 5.0
        scrollView.minimumZoomScale = minScale
        scrollView.zoomScale = minScale
    }

    // Keep the media view centered within the scroll view as you zoom
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard let mediaMessageView = mediaMessageView else {
            owsFailDebug("No media message view.")
            return
        }

        // The scroll view has zoomed, so you need to re-center the contents
        let scrollViewSize = self.scrollViewVisibleSize

        // First assume that mediaMessageView center coincides with the contents center
        // This is correct when the mediaMessageView is bigger than scrollView due to zoom
        var contentCenter = CGPoint(x: (scrollView.contentSize.width / 2), y: (scrollView.contentSize.height / 2))

        let scrollViewCenter = self.scrollViewCenter

        // if mediaMessageView is smaller than the scrollView visible size - fix the content center accordingly
        if self.scrollView.contentSize.width < scrollViewSize.width {
            contentCenter.x = scrollViewCenter.x
        }

        if self.scrollView.contentSize.height < scrollViewSize.height {
            contentCenter.y = scrollViewCenter.y
        }

        mediaMessageView.center = contentCenter
    }

    // return the scroll view center
    private var scrollViewCenter: CGPoint {
        let size = scrollViewVisibleSize
        return CGPoint(x: (size.width / 2), y: (size.height / 2))
    }

    // Return scrollview size without the area overlapping with tab and nav bar.
    private var scrollViewVisibleSize: CGSize {
        let contentInset = scrollView.contentInset
        let scrollViewSize = scrollView.bounds.standardized.size
        let width = scrollViewSize.width - (contentInset.left + contentInset.right)
        let height = scrollViewSize.height - (contentInset.top + contentInset.bottom)
        return CGSize(width: width, height: height)
    }
}

// MARK: -

extension AttachmentPrepViewController: ImageEditorViewDelegate {
    public func imageEditor(presentFullScreenView viewController: UIViewController,
                            isTransparent: Bool) {

        let navigationController = OWSNavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = (isTransparent
            ? .overFullScreen
            : .fullScreen)
        navigationController.ows_prefersStatusBarHidden = true

        if let navigationBar = navigationController.navigationBar as? OWSNavigationBar {
            navigationBar.switchToStyle(.alwaysDarkAndClear)
        } else {
            owsFailDebug("navigationBar was nil or unexpected class")
        }

        self.presentFullScreen(navigationController, animated: false)
    }

    public func imageEditorUpdateNavigationBar() {
        prepDelegate?.prepViewControllerUpdateNavigationBar()
    }

    public func imageEditorUpdateControls() {
        prepDelegate?.prepViewControllerUpdateControls()
    }

    public var imageEditorShouldIgnoreTapGesture: Bool {
        return prepDelegate?.prepViewControllerShouldIgnoreTapGesture ?? false
    }
}

// MARK: -

extension AttachmentPrepViewController: VideoEditorViewDelegate {
    public var videoEditorViewController: UIViewController {
        return self
    }

    public func videoEditorUpdateNavigationBar() {
        prepDelegate?.prepViewControllerUpdateNavigationBar()
    }
}
