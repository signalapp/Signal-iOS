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
public class AttachmentApprovalViewController: OWSViewController, UITextViewDelegate {

    let TAG = "[AttachmentApprovalViewController]"
    weak var delegate: AttachmentApprovalViewControllerDelegate?

    // MARK: Properties

    let attachment: SignalAttachment

    private(set) var bottomToolbar: UIView!
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
        self.bottomToolbar = MessagingToolbar()
////        let bottomToolbar: UIToolbar = makeClearToolbar()
//        self.bottomToolbar = bottomToolbar
//        self.textView = UITextView()
//        textView.delegate = self
//        self.textView.backgroundColor = UIColor.white
//        self.textView.layer.cornerRadius = 4.0
//
//        let textViewItem = UIBarButtonItem(customView: textView)
//        //        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight];
//        textView.translatesAutoresizingMaskIntoConstraints = false
//
//        let sendTitle = NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON", comment: "Label for 'send' button in the 'attachment approval' dialog.")
//        let sendButton = UIBarButtonItem(title:  sendTitle,
//                                         style: .plain,
//                                         target: self,
//                                         action: #selector(sendPressed))
//        sendButton.tintColor = UIColor.white
//
//        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
//        bottomToolbar.items = [textViewItem, sendButton]
////        bottomToolbar.items = [flexibleSpace, sendButton]
//        bottomToolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
////        bottomToolbar.backgroundColor = UIColor.clear
//        bottomToolbar.backgroundColor = UIColor.yellow
//        bottomToolbar.autoSetDimension(.height, toSize: 40, relation: .greaterThanOrEqual)
//
//        let kToolbarMargin: CGFloat = 4.0
//        //        textView.autoSetDimensions(to: CGSize(width: 200, height: 40))
//        textView.autoPinEdge(toSuperviewEdge: .leading, withInset: kToolbarMargin)
//        textView.autoPinEdge(toSuperviewEdge: .top, withInset: kToolbarMargin)
//        // TODO get actualy offset based on button size.
//        let kTrailingOffset: CGFloat = 80
//        textView.autoPinEdge(toSuperviewEdge: .trailing, withInset: kTrailingOffset)
//        textView.autoPinEdge(toSuperviewEdge: .bottom, withInset: kToolbarMargin)
//
//        self.textViewHeightConstraint = textView.autoSetDimension(.height, toSize: kMinTextViewHeight)

//        self.bottomToolbar = MessagingToolbar()
        // Making a toolbar transparent requires setting an empty uiimage

//        self.view.addSubview(bottomToolbar)
//        bottomToolbar.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
//        bottomToolbar.autoPinWidthToSuperview()
//        bottomToolbar.setCompressionResistanceVerticalHigh()
//        bottomToolbar.setContentHuggingVerticalHigh()
    }

    override public var inputAccessoryView: UIView? {
        return self.bottomToolbar
    }

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    class MessagingToolbar: UIToolbar, UITextViewDelegate {
//        let toolbar: UIToolbar
//        let sendButton: UIButton
        let textView: UITextView

        private(set) var textViewHeightConstraint: NSLayoutConstraint!

        private static var kMinTextViewHeight: CGFloat {
            return UIFont.ows_dynamicTypeBody().lineHeight + 4
        }

        init() {
            let textView = UITextView()
            self.textViewHeightConstraint = textView.autoSetDimension(.height, toSize: MessagingToolbar.kMinTextViewHeight)
            self.textView = textView

            super.init(frame: CGRect.zero)

            let kToolbarMargin: CGFloat = 4
            let kSendButtonWidth: CGFloat = 40
            let kMinToolbarHeight: CGFloat = 40

            self.backgroundColor = UIColor.ows_inputToolbarBackground()

            textView.backgroundColor = UIColor.white
            textView.layer.cornerRadius = 4.0
            textView.font = UIFont.ows_dynamicTypeBody()

            let textViewItem = UIBarButtonItem(customView: textView)
            // TODO is this necessary?
            textView.translatesAutoresizingMaskIntoConstraints = false

            let sendTitle = NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON", comment: "Label for 'send' button in the 'attachment approval' dialog.")

            let sendButton = UIBarButtonItem(title:  sendTitle,
                                             style: .plain,
                                             target: self,
                                             action: #selector(sendPressed))
            // TODO
            // self.sendButton.titleLabel.font = [UIFont ows_mediumFontWithSize:16.f];
            // center text alignment
            sendButton.tintColor = UIColor.ows_materialBlue()
            sendButton.width = kSendButtonWidth

            self.items = [textViewItem, sendButton]

            // toolbar doesn't render without some minimum height set.
            self.autoSetDimension(.height, toSize: kMinToolbarHeight, relation: .greaterThanOrEqual)

            // Adding textView to a toolbar item inserts it into a "hostView"
            // This isn't really documentd, but I've verified it works on iOS10
            textView.autoPinEdge(toSuperviewEdge: .leading, withInset: kToolbarMargin)
            textView.autoPinEdge(toSuperviewEdge: .top, withInset: kToolbarMargin)

            let kTrailingOffset: CGFloat = kSendButtonWidth + kToolbarMargin * 2
            textView.autoPinEdge(toSuperviewEdge: .trailing, withInset: kTrailingOffset)
            textView.autoPinEdge(toSuperviewEdge: .bottom, withInset: kToolbarMargin)

            textView.delegate = self
        }

        // MARK: - UITextViewDelegate

        public func textViewDidChange(_ textView: UITextView) {
            Logger.debug("\(self.logTag) in \(#function)")
            //        CGFloat fixedWidth = textView.frame.size.width;
            //        CGSize newSize = [textView sizeThatFits:CGSizeMake(fixedWidth, MAXFLOAT)];
            //        CGRect newFrame = textView.frame;
            //        newFrame.size = CGSizeMake(fmaxf(newSize.width, fixedWidth), newSize.height);
            //        textView.frame = newFrame;
            let fixedWidth = textView.frame.size.width
            let newSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
            //        let newFrame = CGRect(x: textView.frame.origin.x, y: textView.frame.origin.y, width: fixedWidth, height: newSize.height)
            //        Logger.debug("\(self.logTag) oldFrame: \(textView.frame), newFrame: \(newFrame)")

            Logger.debug("\(self.logTag) oldHeight: \(self.textViewHeightConstraint.constant), newHeight: \(newSize.height)")
            // TODO clamp to a max, only when changed
            self.textViewHeightConstraint.constant = max(MessagingToolbar.kMinTextViewHeight, newSize.height)
            setNeedsLayout()
            layoutIfNeeded()
            //        textView.frame = newFrame
        }

//        override func layoutSubviews() {
//            super.layoutSubviews()
//
//            let kMargin = 4
//            let kTextViewHeight = 40
//            let kTextViewWidth = 200
//
//            let kSendButtonHeight = 40
//            let kSendButtonWidth = 100
//
//            self.textView.frame = CGRect(x: kMargin, y: kMargin, width: kTextViewWidth, height: kTextViewHeight)
//            self.sendButton.frame = CGRect(x: kMargin * 2 + kTextViewWidth, y: kMargin, width: kSendButtonWidth, height: kSendButtonHeight)
//            self.frame = CGRect(x: 0, y: 0, width: 320, height: kTextViewHeight + 2 * kMargin)
//            self.bounds = self.frame
//
////            self.textView.sizeToFit()
//
////            let maxHeight = max(self.sendButton.frame.size.height, self.textView.frame.size.height)
////            let fittedFrame = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: maxHeight)
////            self.frame = fittedFrame
////            self.bounds = fittedFrame
//        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
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

//    // MARK: - UITextViewDelegate
//
//    public func textViewDidChange(_ textView: UITextView) {
//        Logger.debug("\(self.logTag) in \(#function)")
////        CGFloat fixedWidth = textView.frame.size.width;
////        CGSize newSize = [textView sizeThatFits:CGSizeMake(fixedWidth, MAXFLOAT)];
////        CGRect newFrame = textView.frame;
////        newFrame.size = CGSizeMake(fmaxf(newSize.width, fixedWidth), newSize.height);
////        textView.frame = newFrame;
//        let fixedWidth = textView.frame.size.width
//        let newSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
////        let newFrame = CGRect(x: textView.frame.origin.x, y: textView.frame.origin.y, width: fixedWidth, height: newSize.height)
////        Logger.debug("\(self.logTag) oldFrame: \(textView.frame), newFrame: \(newFrame)")
//
//        Logger.debug("\(self.logTag) oldHeight: \(self.textViewHeightConstraint.constant), newHeight: \(newSize.height)")
//        // TODO clamp to a max.
//        self.textViewHeightConstraint.constant = max(kMinTextViewHeight, newSize.height)
//        self.bottomToolbar.setNeedsLayout()
//        self.bottomToolbar.layoutIfNeeded()
////        textView.frame = newFrame
//    }
//    - (void)textViewDidChange:(UITextView *)textView

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
