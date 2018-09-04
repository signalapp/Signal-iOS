//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer
import YYImage
import SignalServiceKit

@objc
public enum MediaMessageViewMode: UInt {
    case large
    case small
    case attachmentApproval
}

@objc
public class MediaMessageView: UIView, OWSAudioPlayerDelegate {

    // MARK: Properties

    @objc
    public let mode: MediaMessageViewMode

    @objc
    public let attachment: SignalAttachment

    @objc
    public var audioPlayer: OWSAudioPlayer?

    @objc
    public var audioPlayButton: UIButton?

    @objc
    public var videoPlayButton: UIImageView?

    @objc
    public var playbackState = AudioPlaybackState.stopped {
        didSet {
            AssertIsOnMainThread()

            ensureButtonState()
        }
    }

    @objc
    public var audioProgressSeconds: CGFloat = 0

    @objc
    public var audioDurationSeconds: CGFloat = 0

    @objc
    public var contentView: UIView?

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // Currently we only use one mode (AttachmentApproval), so we could simplify this class, but it's kind
    // of nice that it's written in a flexible way in case we'd want to use it elsewhere again in the future.
    @objc
    public required init(attachment: SignalAttachment, mode: MediaMessageViewMode) {
        assert(!attachment.hasError)
        self.attachment = attachment
        self.mode = mode
        super.init(frame: CGRect.zero)

        createViews()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Create Views

    private func createViews() {
        if attachment.isAnimatedImage {
            createAnimatedPreview()
        } else if attachment.isImage {
            createImagePreview()
        } else if attachment.isVideo {
            createVideoPreview()
        } else if attachment.isAudio {
            createAudioPreview()
        } else {
            createGenericPreview()
        }
    }

    private func wrapViewsInVerticalStack(subviews: [UIView]) -> UIView {
        assert(subviews.count > 0)

        let stackView = UIView()

        var lastView: UIView?
        for subview in subviews {

            stackView.addSubview(subview)
            subview.autoHCenterInSuperview()

            if lastView == nil {
                subview.autoPinEdge(toSuperviewEdge: .top)
            } else {
                subview.autoPinEdge(.top, to: .bottom, of: lastView!, withOffset: stackSpacing())
            }

            lastView = subview
        }

        lastView?.autoPinEdge(toSuperviewEdge: .bottom)

        return stackView
    }

    private func stackSpacing() -> CGFloat {
        switch mode {
        case .large, .attachmentApproval:
            return CGFloat(10)
        case .small:
            return CGFloat(5)
        }
    }

    private func createAudioPreview() {
        guard let dataUrl = attachment.dataUrl else {
            createGenericPreview()
            return
        }

        audioPlayer = OWSAudioPlayer(mediaUrl: dataUrl, delegate: self)

        var subviews = [UIView]()

        let audioPlayButton = UIButton()
        self.audioPlayButton = audioPlayButton
        setAudioIconToPlay()
        audioPlayButton.imageView?.layer.minificationFilter = kCAFilterTrilinear
        audioPlayButton.imageView?.layer.magnificationFilter = kCAFilterTrilinear
        audioPlayButton.addTarget(self, action: #selector(audioPlayButtonPressed), for: .touchUpInside)
        let buttonSize = createHeroViewSize()
        audioPlayButton.autoSetDimension(.width, toSize: buttonSize)
        audioPlayButton.autoSetDimension(.height, toSize: buttonSize)
        subviews.append(audioPlayButton)

        let fileNameLabel = createFileNameLabel()
        if let fileNameLabel = fileNameLabel {
            subviews.append(fileNameLabel)
        }

        let fileSizeLabel = createFileSizeLabel()
        subviews.append(fileSizeLabel)

        let stackView = wrapViewsInVerticalStack(subviews: subviews)
        self.addSubview(stackView)
        fileNameLabel?.autoPinWidthToSuperview(withMargin: 32)

        // We want to center the stackView in it's superview while also ensuring
        // it's superview is big enough to contain it.
        stackView.autoPinWidthToSuperview()
        stackView.autoVCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultLow) {
            stackView.autoPinHeightToSuperview()
        }
        stackView.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0, relation: .greaterThanOrEqual)
    }

    private func createAnimatedPreview() {
        guard attachment.isValidImage else {
            createGenericPreview()
            return
        }
        guard let dataUrl = attachment.dataUrl else {
            createGenericPreview()
            return
        }
        guard let image = YYImage(contentsOfFile: dataUrl.path) else {
            createGenericPreview()
            return
        }
        guard image.size.width > 0 && image.size.height > 0 else {
            createGenericPreview()
            return
        }
        let animatedImageView = YYAnimatedImageView()
        animatedImageView.image = image
        let aspectRatio = image.size.width / image.size.height
        addSubviewWithScaleAspectFitLayout(view: animatedImageView, aspectRatio: aspectRatio)
        contentView = animatedImageView
    }

    private func addSubviewWithScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) {
        self.addSubview(view)
        // This emulates the behavior of contentMode = .scaleAspectFit using
        // iOS auto layout constraints.  
        //
        // This allows ConversationInputToolbar to place the "cancel" button
        // in the upper-right hand corner of the preview content.
        view.autoCenterInSuperview()
        view.autoPin(toAspectRatio: aspectRatio)
        view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
        view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
    }

    private func createImagePreview() {
        guard attachment.isValidImage else {
            createGenericPreview()
            return
        }
        guard let image = attachment.image() else {
            createGenericPreview()
            return
        }
        guard image.size.width > 0 && image.size.height > 0 else {
            createGenericPreview()
            return
        }

        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = kCAFilterTrilinear
        imageView.layer.magnificationFilter = kCAFilterTrilinear
        let aspectRatio = image.size.width / image.size.height
        addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
        contentView = imageView
    }

    private func createVideoPreview() {
        guard attachment.isValidVideo else {
            createGenericPreview()
            return
        }
        guard let image = attachment.videoPreview() else {
            createGenericPreview()
            return
        }
        guard image.size.width > 0 && image.size.height > 0 else {
            createGenericPreview()
            return
        }

        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = kCAFilterTrilinear
        imageView.layer.magnificationFilter = kCAFilterTrilinear
        let aspectRatio = image.size.width / image.size.height
        addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
        contentView = imageView

        // attachment approval provides it's own play button to keep it
        // at the proper zoom scale.
        if mode != .attachmentApproval {
            let videoPlayIcon = UIImage(named: "play_button")!
            let videoPlayButton = UIImageView(image: videoPlayIcon)
            self.videoPlayButton = videoPlayButton
            videoPlayButton.contentMode = .scaleAspectFit
            self.addSubview(videoPlayButton)
            videoPlayButton.autoCenterInSuperview()
        }
    }

    private func createGenericPreview() {
        var subviews = [UIView]()

        let imageView = createHeroImageView(imageName: "file-thin-black-filled-large")
        subviews.append(imageView)

        let fileNameLabel = createFileNameLabel()
        if let fileNameLabel = fileNameLabel {
            subviews.append(fileNameLabel)
        }

        let fileSizeLabel = createFileSizeLabel()
        subviews.append(fileSizeLabel)

        let stackView = wrapViewsInVerticalStack(subviews: subviews)
        self.addSubview(stackView)
        fileNameLabel?.autoPinWidthToSuperview(withMargin: 32)

        // We want to center the stackView in it's superview while also ensuring
        // it's superview is big enough to contain it.
        stackView.autoPinWidthToSuperview()
        stackView.autoVCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultLow) {
            stackView.autoPinHeightToSuperview()
        }
        stackView.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0, relation: .greaterThanOrEqual)
    }

    private func createHeroViewSize() -> CGFloat {
        switch mode {
        case .large:
            return ScaleFromIPhone5To7Plus(175, 225)
        case .attachmentApproval:
            return ScaleFromIPhone5(100)
        case .small:
            return ScaleFromIPhone5To7Plus(80, 80)
        }
    }

    private func createHeroImageView(imageName: String) -> UIView {
        let imageSize = createHeroViewSize()

        let image = UIImage(named: imageName)
        assert(image != nil)
        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = kCAFilterTrilinear
        imageView.layer.magnificationFilter = kCAFilterTrilinear
        imageView.layer.shadowColor = UIColor.black.cgColor
        let shadowScaling = 5.0
        imageView.layer.shadowRadius = CGFloat(2.0 * shadowScaling)
        imageView.layer.shadowOpacity = 0.25
        imageView.layer.shadowOffset = CGSize(width: 0.75 * shadowScaling, height: 0.75 * shadowScaling)
        imageView.autoSetDimension(.width, toSize: imageSize)
        imageView.autoSetDimension(.height, toSize: imageSize)

        return imageView
    }

    private func labelFont() -> UIFont {
        switch mode {
        case .large, .attachmentApproval:
            return UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(18, 24))
        case .small:
            return UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(14, 14))
        }
    }

    private var controlTintColor: UIColor {
        switch mode {
        case .small, .large:
            return UIColor.ows_materialBlue
        case .attachmentApproval:
            return UIColor.white
        }
    }

    private func formattedFileExtension() -> String? {
        guard let fileExtension = attachment.fileExtension else {
            return nil
        }

        return String(format: NSLocalizedString("ATTACHMENT_APPROVAL_FILE_EXTENSION_FORMAT",
                                               comment: "Format string for file extension label in call interstitial view"),
                      fileExtension.uppercased())
    }

    public func formattedFileName() -> String? {
        guard let sourceFilename = attachment.sourceFilename else {
            return nil
        }
        let filename = sourceFilename.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard filename.count > 0 else {
            return nil
        }
        return filename
    }

    private func createFileNameLabel() -> UIView? {
        let filename = formattedFileName() ?? formattedFileExtension()

        guard filename != nil else {
            return nil
        }

        let label = UILabel()
        label.text = filename
        label.textColor = controlTintColor
        label.font = labelFont()
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    private func createFileSizeLabel() -> UIView {
        let label = UILabel()
        let fileSize = attachment.dataLength
        label.text = String(format: NSLocalizedString("ATTACHMENT_APPROVAL_FILE_SIZE_FORMAT",
                                                     comment: "Format string for file size label in call interstitial view. Embeds: {{file size as 'N mb' or 'N kb'}}."),
                            OWSFormat.formatFileSize(UInt(fileSize)))

        label.textColor = controlTintColor
        label.font = labelFont()
        label.textAlignment = .center

        return label
    }

    // MARK: - Event Handlers

    @objc
    func audioPlayButtonPressed(sender: UIButton) {
        audioPlayer?.togglePlayState()
    }

    // MARK: - OWSAudioPlayerDelegate

    public func audioPlaybackState() -> AudioPlaybackState {
        return playbackState
    }

    public func setAudioPlaybackState(_ value: AudioPlaybackState) {
        playbackState = value
    }

    private func ensureButtonState() {
        if playbackState == .playing {
            setAudioIconToPause()
        } else {
            setAudioIconToPlay()
        }
    }

    public func setAudioProgress(_ progress: CGFloat, duration: CGFloat) {
        audioProgressSeconds = progress
        audioDurationSeconds = duration
    }

    private func setAudioIconToPlay() {
        let image = UIImage(named: "audio_play_black_large")?.withRenderingMode(.alwaysTemplate)
        assert(image != nil)
        audioPlayButton?.setImage(image, for: .normal)
        audioPlayButton?.imageView?.tintColor = controlTintColor
    }

    private func setAudioIconToPause() {
        let image = UIImage(named: "audio_pause_black_large")?.withRenderingMode(.alwaysTemplate)
        assert(image != nil)
        audioPlayButton?.setImage(image, for: .normal)
        audioPlayButton?.imageView?.tintColor = controlTintColor
    }
}
