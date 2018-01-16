//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer

@objc
public protocol AttachmentApprovalViewControllerDelegate: class {
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachment attachment: SignalAttachment)
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didCancelAttachment attachment: SignalAttachment)
}

@objc
public class AttachmentApprovalViewController: OWSViewController, CaptioningToolbarDelegate {

    let TAG = "[AttachmentApprovalViewController]"
    weak var delegate: AttachmentApprovalViewControllerDelegate?

    // We sometimes shrink the attachment view so that it remains somewhat visible
    // when the keyboard is presented.
    enum AttachmentViewScale {
        case fullsize, compact
    }

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

        if isZoomable {
            // Add top and bottom gradients to ensure toolbar controls are legible
            // when placed over image/video preview which may be a clashing color.
            let topGradient = GradientView(from: backgroundColor, to: UIColor.clear)
            self.view.addSubview(topGradient)
            topGradient.autoPinWidthToSuperview()
            topGradient.autoPinEdge(toSuperviewEdge: .top)
            topGradient.autoSetDimension(.height, toSize: ScaleFromIPhone5(60))
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
        let captioningToolbar = CaptioningToolbar()
        captioningToolbar.captioningToolbarDelegate = self
        self.bottomToolbar = captioningToolbar
    }

    override public var inputAccessoryView: UIView? {
        self.bottomToolbar.layoutIfNeeded()
        return self.bottomToolbar
    }

    override public var canBecomeFirstResponder: Bool {
        return true
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
        // FIXME - use built in AVPlayer controls like MediaDetailViewController
//        mediaMessageView.playVideo()
    }

    func cancelPressed(sender: UIButton) {
        self.delegate?.attachmentApproval(self, didCancelAttachment: attachment)
    }

    // MARK: CaptioningToolbarDelegate

    func captioningToolbarDidBeginEditing(_ captioningToolbar: CaptioningToolbar) {
        self.scaleAttachmentView(.compact)
    }

    func captioningToolbarDidEndEditing(_ captioningToolbar: CaptioningToolbar) {
        self.scaleAttachmentView(.fullsize)
    }

    func captioningToolbarDidTapSend(_ captioningToolbar: CaptioningToolbar, captionText: String?) {
        self.approveAttachment(captionText: captionText)
    }

    func captioningToolbar(_ captioningToolbar: CaptioningToolbar, didChangeTextViewHeight newHeight: CGFloat) {
        Logger.info("Changed height: \(newHeight)")
    }

    // MARK: Helpers

    var isZoomable: Bool {
        return attachment.isImage || attachment.isVideo
    }

    private func approveAttachment(captionText: String?) {
        // Toolbar flickers in and out if there are errors
        // and remains visible momentarily after share extension is dismissed.
        // It's easiest to just hide it at this point since we're done with it.
        shouldAllowAttachmentViewResizing = false
        bottomToolbar.isUserInteractionEnabled = false
        bottomToolbar.isHidden = true

        attachment.captionText = captionText
        delegate?.attachmentApproval(self, didApproveAttachment: attachment)
    }

    // When the keyboard is popped, it can obscure the attachment view.
    // so we sometimes allow resizing the attachment.
    private var shouldAllowAttachmentViewResizing: Bool = true

    private func scaleAttachmentView(_ fit: AttachmentViewScale) {
        guard shouldAllowAttachmentViewResizing else {
            if self.scrollView.transform != CGAffineTransform.identity {
                UIView.animate(withDuration: 0.2) {
                    self.scrollView.transform = CGAffineTransform.identity
                }
            }
            return
        }

        switch fit {
        case .fullsize:
            UIView.animate(withDuration: 0.2) {
                self.scrollView.transform = CGAffineTransform.identity
            }
        case .compact:
            UIView.animate(withDuration: 0.2) {
                let kScaleFactor: CGFloat = 0.7
                let scale = CGAffineTransform(scaleX: kScaleFactor, y: kScaleFactor)

                let originalHeight = self.scrollView.bounds.size.height

                // Position the new scaled item to be centered with respect
                // to it's new size.
                let heightDelta = originalHeight * (1 - kScaleFactor)
                let translate = CGAffineTransform(translationX: 0, y: -heightDelta / 2)

                self.scrollView.transform = scale.concatenating(translate)
            }
        }
    }
}

extension AttachmentApprovalViewController: UIScrollViewDelegate {

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        if isZoomable {
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

protocol CaptioningToolbarDelegate: class {
    func captioningToolbarDidTapSend(_ captioningToolbar: CaptioningToolbar, captionText: String?)
    func captioningToolbar(_ captioningToolbar: CaptioningToolbar, didChangeTextViewHeight newHeight: CGFloat)
    func captioningToolbarDidBeginEditing(_ captioningToolbar: CaptioningToolbar)
    func captioningToolbarDidEndEditing(_ captioningToolbar: CaptioningToolbar)
}

class CaptioningToolbar: UIView, UITextViewDelegate {

    weak var captioningToolbarDelegate: CaptioningToolbarDelegate?
    private let sendButton: UIButton
    private let textView: UITextView
    private let bottomGradient: GradientView

    // Layout Constants
    var maxTextViewHeight: CGFloat {
        // About ~4 lines in portrait and ~3 lines in landscape.
        // Otherwise we risk obscuring too much of the content.
        return UIDevice.current.orientation.isPortrait ? 160 : 100
    }

    let kMinTextViewHeight: CGFloat = 38
    var textViewHeight: CGFloat {
        didSet {
            self.captioningToolbarDelegate?.captioningToolbar(self, didChangeTextViewHeight: textViewHeight)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    class MessageTextView: UITextView {
        // When creating new lines, contentOffset is animated, but because because
        // we are simultaneously resizing the text view, this can cause the
        // text in the textview to be "too high" in the text view.
        // Solution is to disable animation for setting content offset.
        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            super.setContentOffset(contentOffset, animated: false)
        }
    }

    let kSendButtonShadowOffset: CGFloat = 1
    init() {
        self.sendButton = UIButton(type: .system)
        self.bottomGradient = GradientView(from: UIColor.clear, to: UIColor.black)
        self.textView =  MessageTextView()
        self.textViewHeight = kMinTextViewHeight

        super.init(frame: CGRect.zero)

        self.backgroundColor = UIColor.clear

        textView.delegate = self
        textView.backgroundColor = UIColor.white
        textView.layer.cornerRadius = 4.0
        textView.addBorder(with: UIColor.lightGray)
        textView.font = UIFont.ows_dynamicTypeBody()
        textView.returnKeyType = .done

        let sendTitle = NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON", comment: "Label for 'send' button in the 'attachment approval' dialog.")
        sendButton.setTitle(sendTitle, for: .normal)
        sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)

        sendButton.titleLabel?.font = UIFont.ows_mediumFont(withSize: 16)
        sendButton.titleLabel?.textAlignment = .center
        sendButton.tintColor = UIColor.white
        sendButton.backgroundColor = UIColor.ows_systemPrimaryButton
        sendButton.layer.cornerRadius = 4

        // Send Button Shadow - without this the send button bottom doesn't align with the toolbar.
        sendButton.layer.shadowColor = UIColor.darkGray.cgColor
        sendButton.layer.shadowOffset = CGSize(width: 0, height: kSendButtonShadowOffset)
        sendButton.layer.shadowOpacity = 0.8
        sendButton.layer.shadowRadius = 0.0
        sendButton.layer.masksToBounds = false

        // Increase hit area of send button
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        addSubview(bottomGradient)
        addSubview(sendButton)
        addSubview(textView)

        sendButton.sizeToFit()
    }

    func didTapSend() {
        self.captioningToolbarDelegate?.captioningToolbarDidTapSend(self, captionText: self.textView.text)
    }

    // MARK: - UIView Overrides

    // We do progammatic layout, explicitly computing and setting frames since autoLayout does
    // not seem to work with inputAccessory views, even when forcing a layout.
    override func layoutSubviews() {
        super.layoutSubviews()

        let kToolbarHMargin: CGFloat = 8
        let kToolbarVMargin: CGFloat = 8

        let sendButtonWidth = sendButton.frame.size.width

        let kOriginalToolbarHeight = kMinTextViewHeight + 2 * kToolbarVMargin
        // Assume send button has proper size.
        let textViewWidth = frame.size.width - 3 * kToolbarHMargin - sendButtonWidth

        // determine height given a fixed width
        let textViewHeight = clampedTextViewHeight(fixedWidth: textViewWidth)
        let newToolbarHeight = textViewHeight + 2 * kToolbarVMargin
        self.frame.size.height = newToolbarHeight
        let toolbarHeightOffset = newToolbarHeight - kOriginalToolbarHeight

        let textViewY = kToolbarVMargin - toolbarHeightOffset
        textView.frame = CGRect(x: kToolbarHMargin, y: textViewY, width: textViewWidth, height: textViewHeight)
        if (self.textViewHeight != textViewHeight) {
            // textViewHeight changed without textView's content changing, this can happen
            // when the user flips their device orientation after writing a caption.
            self.textViewHeight = textViewHeight
        }

        // Send Button

        // position in bottom right corner
        let sendButtonX = frame.size.width - kToolbarHMargin - sendButton.frame.size.width
        let sendButtonY = kOriginalToolbarHeight - kToolbarVMargin - sendButton.frame.size.height - kSendButtonShadowOffset
        sendButton.frame = CGRect(origin: CGPoint(x: sendButtonX, y: sendButtonY), size: sendButton.frame.size)
        sendButton.frame.size.height = kMinTextViewHeight - kSendButtonShadowOffset - textView.layer.borderWidth

        let bottomGradientHeight = ScaleFromIPhone5(100)
        let bottomGradientY = kOriginalToolbarHeight - bottomGradientHeight
        bottomGradient.frame = CGRect(x: 0, y: bottomGradientY, width: frame.size.width, height: bottomGradientHeight)
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        // compute new height assuming width is unchanged
        let currentSize = textView.frame.size
        let newHeight = clampedTextViewHeight(fixedWidth: currentSize.width)

        if newHeight != self.textViewHeight {
            Logger.debug("\(self.logTag) TextView height changed: \(self.textViewHeight) -> \(newHeight)")
            self.textViewHeight = newHeight
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Though we can wrap the text, we don't want to encourage multline captions, plus a "done" button
        // allows the user to get the keyboard out of the way while in the attachment approval view.
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        } else {
            return true
        }
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        self.captioningToolbarDelegate?.captioningToolbarDidBeginEditing(self)
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        self.captioningToolbarDelegate?.captioningToolbarDidEndEditing(self)
    }

    // MARK: - Helpers

    private func clampedTextViewHeight(fixedWidth: CGFloat) -> CGFloat {
        let contentSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
        return Clamp(contentSize.height, kMinTextViewHeight, maxTextViewHeight)
    }

}
