//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer

@objc
public protocol AttachmentApprovalViewControllerDelegate: class {
    func didApproveAttachment(attachment: SignalAttachment)
    func didCancelAttachment(attachment: SignalAttachment)
}

@objc
public class AttachmentApprovalViewController: OWSViewController {

    let TAG = "[AttachmentApprovalViewController]"
    weak var delegate: AttachmentApprovalViewControllerDelegate?

    // MARK: Properties

    let attachment: SignalAttachment

    private(set) var bottomToolbar: UIToolbar!
    private(set) var mediaMessageView: MediaMessageView!
    private(set) var scrollView: UIScrollView!

    // MARK: Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("unimplemented")
    }

    @objc
    required public init(attachment: SignalAttachment, delegate: AttachmentApprovalViewControllerDelegate) {
        assert(!attachment.hasError)
        self.attachment = attachment
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = dialogTitle()
    }

    override public func viewWillLayoutSubviews() {
        Logger.debug("\(logTag) in \(#function)")
        super.viewWillLayoutSubviews()

        // e.g. if flipping to/from landscape
        updateMinZoomScaleForSize(view.bounds.size)
    }

    private func dialogTitle() -> String {
        guard let filename = mediaMessageView.formattedFileName() else {
            return NSLocalizedString("ATTACHMENT_APPROVAL_DIALOG_TITLE",
                                     comment: "Title for the 'attachment approval' dialog.")
        }
        return filename
    }

    override public func viewWillAppear(_ animated: Bool) {
        Logger.debug("\(logTag) in \(#function)")
        super.viewWillAppear(animated)

        mediaMessageView.viewWillAppear(animated)
    }

    override public func viewDidAppear(_ animated: Bool) {
        Logger.debug("\(logTag) in \(#function)")
        super.viewDidAppear(animated)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        Logger.debug("\(logTag) in \(#function)")
        super.viewWillDisappear(animated)

        mediaMessageView.viewWillDisappear(animated)
    }

    // MARK: - Create Views

    public override func loadView() {

        self.view = UIView()

        self.mediaMessageView = MediaMessageView(attachment: attachment, mode: .attachmentApproval)

        // Scroll View - used to zoom/pan on images and video
        scrollView = UIScrollView()
        view.addSubview(scrollView)

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false

        // Panning should stop pretty soon after the user stops scrolling
        scrollView.decelerationRate = UIScrollViewDecelerationRateFast

        // We want scroll view content up and behind the system status bar content
        // but we want other content (e.g. bar buttons) to respect the top layout guide.
        self.automaticallyAdjustsScrollViewInsets = false

        scrollView.autoPinEdgesToSuperviewEdges()

        let backgroundColor = UIColor.black
        self.view.backgroundColor = backgroundColor

        // Create full screen container view so the scrollView
        // can compute an appropriate content size in which to center
        // our media view.
        let containerView = UIView.container()
        scrollView.addSubview(containerView)
        containerView.autoPinEdgesToSuperviewEdges()
        containerView.autoMatch(.height, to: .height, of: self.view)
        containerView.autoMatch(.width, to: .width, of: self.view)

        containerView.addSubview(mediaMessageView)
        mediaMessageView.autoPinEdgesToSuperviewEdges()

        if attachment.isImage || attachment.isVideo {
            // Add top and bottom gradients to ensure toolbar controls are legible
            // when placed over image/video preview which may be a clashing color.
            let topGradient = GradientView(from: backgroundColor, to: UIColor.clear)
            self.view.addSubview(topGradient)
            topGradient.autoPinWidthToSuperview()
            topGradient.autoPinEdge(toSuperviewEdge: .top)
            topGradient.autoSetDimension(.height, toSize: ScaleFromIPhone5(60))

            let bottomGradient = GradientView(from: UIColor.clear, to: backgroundColor)
            self.view.addSubview(bottomGradient)
            bottomGradient.autoPinWidthToSuperview()
            bottomGradient.autoPinEdge(toSuperviewEdge: .bottom)
            bottomGradient.autoSetDimension(.height, toSize: ScaleFromIPhone5(100))
        }

        // Hide the play button embedded in the MediaView and replace it with our own.
        // This allows us to zoom in on the media view without zooming in on the button
        if attachment.isVideo {
            self.mediaMessageView.videoPlayButton?.isHidden = true
            let playButton = UIButton()
            playButton.accessibilityLabel = NSLocalizedString("PLAY_BUTTON_ACCESSABILITY_LABEL", comment: "accessability label for button to start media playback")
            playButton.setBackgroundImage(#imageLiteral(resourceName: "play_button"), for: .normal)
            playButton.contentMode = .scaleAspectFit

            let playButtonWidth = ScaleFromIPhone5(70)
            playButton.autoSetDimensions(to: CGSize(width: playButtonWidth, height: playButtonWidth))
            self.view.addSubview(playButton)

            playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
            playButton.autoCenterInSuperview()
        }

        // Top Toolbar
        let topToolbar = makeClearToolbar()

        self.view.addSubview(topToolbar)
        topToolbar.autoPinWidthToSuperview()
        topToolbar.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        topToolbar.setContentHuggingVerticalHigh()
        topToolbar.setCompressionResistanceVerticalHigh()

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(cancelPressed))
        cancelButton.tintColor = UIColor.white
        topToolbar.items = [cancelButton]

        // Bottom Toolbar
        self.bottomToolbar = makeClearToolbar()
        // Making a toolbar transparent requires setting an empty uiimage
        bottomToolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        bottomToolbar.backgroundColor = UIColor.clear

        let sendTitle = NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON", comment: "Label for 'send' button in the 'attachment approval' dialog.")
        let sendButton = UIBarButtonItem(title:  sendTitle,
                                         style: .plain,
                                         target: self,
                                         action: #selector(sendPressed))
        sendButton.tintColor = UIColor.white

        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        bottomToolbar.items = [flexibleSpace, sendButton]

        self.view.addSubview(bottomToolbar)
        bottomToolbar.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        bottomToolbar.autoPinWidthToSuperview()
        bottomToolbar.setCompressionResistanceVerticalHigh()
        bottomToolbar.setContentHuggingVerticalHigh()
    }

    private func makeClearToolbar() -> UIToolbar {
        let toolbar = UIToolbar()

        toolbar.backgroundColor = UIColor.clear

        // Making a toolbar transparent requires setting an empty uiimage
        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)

        // hide 1px top-border
        toolbar.clipsToBounds = true

        return toolbar
    }

    // MARK: - Event Handlers

    @objc
    public func playButtonTapped() {
        mediaMessageView.playVideo()
    }

    func cancelPressed(sender: UIButton) {
        self.delegate?.didCancelAttachment(attachment: attachment)
    }

    func sendPressed(sender: UIButton) {
        // disable controls after send was tapped.
        self.bottomToolbar.isUserInteractionEnabled = false

        // FIXME
        // this is just a temporary hack to provide some UI
        // until we have a proper progress indicator
        let activityIndicatorView = UIActivityIndicatorView()
        view.addSubview(activityIndicatorView)
        activityIndicatorView.autoCenterInSuperview()
        activityIndicatorView.startAnimating()

        self.delegate?.didApproveAttachment(attachment: attachment)
    }
}

extension AttachmentApprovalViewController: UIScrollViewDelegate {

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        if attachment.isImage || attachment.isVideo {
            return mediaMessageView
        } else {
            // don't zoom for audio or generic attachments.
            return nil
        }
    }

    fileprivate func updateMinZoomScaleForSize(_ size: CGSize) {
        Logger.debug("\(logTag) in \(#function)")

        // Ensure bounds have been computed
        mediaMessageView.layoutIfNeeded()
        guard mediaMessageView.bounds.width > 0, mediaMessageView.bounds.height > 0 else {
            Logger.warn("\(logTag) bad bounds in \(#function)")
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

        self.mediaMessageView.center = contentCenter
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

private class GradientView: UIView {

    let gradientLayer = CAGradientLayer()

    required init(from fromColor: UIColor, to toColor: UIColor) {
        gradientLayer.colors = [fromColor.cgColor, toColor.cgColor]
        super.init(frame: CGRect.zero)

        self.layer.addSublayer(gradientLayer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = self.bounds
    }
}
