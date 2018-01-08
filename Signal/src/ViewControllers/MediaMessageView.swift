//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer

@objc
enum MediaMessageViewMode: UInt {
    case large
    case small
}

class MediaMessageView: UIView, OWSAudioAttachmentPlayerDelegate {

    let TAG = "[MediaMessageView]"

    // MARK: Properties

    let mode: MediaMessageViewMode

    // If this is for a persisted interaction, viewItem and attachmentStream will not be nil
    // If this is for an attachmet draft, before sending, viewItem and attachmentStream will be nil
    var viewItem: ConversationViewItem?
    var attachmentStream: TSAttachmentStream?

    let attachment: SignalAttachment

    var videoPlayer: MPMoviePlayerController?

    var audioPlayer: OWSAudioAttachmentPlayer?
    var audioPlayButton: UIButton?
    var playbackState = AudioPlaybackState.stopped {
        didSet {
            AssertIsOnMainThread()

            ensureButtonState()
        }
    }

    var audioProgressSeconds: CGFloat = 0
    var audioDurationSeconds: CGFloat = 0

    var contentView: UIView?

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("\(#function) is unimplemented.")
    }

    convenience init(attachment: SignalAttachment, mode: MediaMessageViewMode) {
        self.init(attachment: attachment, mode: mode, viewItem: nil, attachmentStream: nil)
    }

    required init(attachment: SignalAttachment, mode: MediaMessageViewMode, viewItem: ConversationViewItem?, attachmentStream: TSAttachmentStream?) {
        assert(!attachment.hasError)
        self.attachment = attachment
        self.mode = mode
        self.viewItem = viewItem
        self.attachmentStream = attachmentStream
        super.init(frame: CGRect.zero)

        createViews()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: View Lifecycle

    func viewWillAppear(_ animated: Bool) {
        ViewControllerUtils.setAudioIgnoresHardwareMuteSwitch(true)
    }

    func viewWillDisappear(_ animated: Bool) {
        ViewControllerUtils.setAudioIgnoresHardwareMuteSwitch(false)
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
        case .large:
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

        audioPlayer = OWSAudioAttachmentPlayer(mediaUrl: dataUrl, delegate: self)

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
        stackView.autoPinWidthToSuperview()
        stackView.autoVCenterInSuperview()
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
        addSubviewWithScaleAspectFitLayout(view:animatedImageView, aspectRatio:aspectRatio)
        contentView = animatedImageView

        animatedImageView.isUserInteractionEnabled = true
        animatedImageView.addGestureRecognizer(UITapGestureRecognizer(target:self, action:#selector(imageTapped)))
    }

    private func addSubviewWithScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) {
        self.addSubview(view)
        // This emulates the behavior of contentMode = .scaleAspectFit using
        // iOS auto layout constraints.  
        //
        // This allows ConversationInputToolbar to place the "cancel" button
        // in the upper-right hand corner of the preview content.
        view.autoCenterInSuperview()
        view.autoPin(toAspectRatio:aspectRatio)
        view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
        view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
    }

    private func createImagePreview() {
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
        addSubviewWithScaleAspectFitLayout(view:imageView, aspectRatio:aspectRatio)
        contentView = imageView

        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target:self, action:#selector(imageTapped)))
    }

    private func createVideoPreview() {
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
        addSubviewWithScaleAspectFitLayout(view:imageView, aspectRatio:aspectRatio)
        contentView = imageView

        let videoPlayIcon = UIImage(named:"play_button")
        let videoPlayButton = UIImageView(image:videoPlayIcon)
        imageView.addSubview(videoPlayButton)
        videoPlayButton.autoCenterInSuperview()

        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target:self, action:#selector(videoTapped)))
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
        stackView.autoPinWidthToSuperview()
        stackView.autoVCenterInSuperview()
    }

    private func createHeroViewSize() -> CGFloat {
        switch mode {
        case .large:
            return ScaleFromIPhone5To7Plus(175, 225)
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
        case .large:
            return UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(18, 24))
        case .small:
            return UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(14, 14))
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
        guard filename.characters.count > 0 else {
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
        label.textColor = UIColor.ows_materialBlue()
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
                            ViewControllerUtils.formatFileSize(UInt(fileSize)))

        label.textColor = UIColor.ows_materialBlue()
        label.font = labelFont()
        label.textAlignment = .center

        return label
    }

    // MARK: - Event Handlers

    func audioPlayButtonPressed(sender: UIButton) {
        audioPlayer?.togglePlayState()
    }

    // MARK: - OWSAudioAttachmentPlayerDelegate

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
        audioPlayButton?.imageView?.tintColor = UIColor.ows_materialBlue()
    }

    private func setAudioIconToPause() {
        let image = UIImage(named: "audio_pause_black_large")?.withRenderingMode(.alwaysTemplate)
        assert(image != nil)
        audioPlayButton?.setImage(image, for: .normal)
        audioPlayButton?.imageView?.tintColor = UIColor.ows_materialBlue()
    }

    // MARK: - Full Screen Image

    func imageTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard let fromView = sender.view else {
            return
        }
        showMediaDetailViewController(fromView: fromView)
    }

    private func fromViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while true {
            if responder == nil {
                return nil
            }
            if let viewController = responder as? UIViewController {
                return viewController
            }
            responder = responder?.next
        }
    }

    // MARK: - Video Playback

    func videoTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard let fromView = sender.view else {
            return
        }
        showMediaDetailViewController(fromView: fromView)
    }

    func showMediaDetailViewController(fromView: UIView) {
        guard let fromViewController = fromViewController() else {
            return
        }
        let window = UIApplication.shared.keyWindow
        let convertedRect = fromView.convert(fromView.bounds, to:window)

        let viewController: MediaDetailViewController = {
            if let viewItem = self.viewItem, let attachmentStream = self.attachmentStream {
                return MediaDetailViewController(attachmentStream: attachmentStream, from: convertedRect, viewItem: viewItem)
            } else {
                // e.g. when MediaMessageView does not belong to a persisted interaction, e.g. approval view.
                return MediaDetailViewController(attachment: attachment, from:convertedRect)
            }
        }()

        viewController.present(from:fromViewController)
    }
}
