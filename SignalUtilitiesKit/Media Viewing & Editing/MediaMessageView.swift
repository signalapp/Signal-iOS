//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer
import YYImage
import NVActivityIndicatorView
import SessionUIKit

public class MediaMessageView: UIView, OWSAudioPlayerDelegate {
    public enum Mode: UInt {
        case large
        case small
        case attachmentApproval
    }

    // MARK: Properties

    public let mode: Mode
    public let attachment: SignalAttachment

    public var audioPlayer: OWSAudioPlayer?
    
    private var linkPreviewInfo: (url: String, draft: OWSLinkPreviewDraft?)?
    

    public var playbackState = AudioPlaybackState.stopped {
        didSet {
            AssertIsOnMainThread()

            ensureButtonState()
        }
    }

    public var audioProgressSeconds: CGFloat = 0
    public var audioDurationSeconds: CGFloat = 0

    public var contentView: UIView?
    
    

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // Currently we only use one mode (AttachmentApproval), so we could simplify this class, but it's kind
    // of nice that it's written in a flexible way in case we'd want to use it elsewhere again in the future.
    public required init(attachment: SignalAttachment, mode: MediaMessageView.Mode) {
        if attachment.hasError { owsFailDebug(attachment.error.debugDescription) }
        
        self.attachment = attachment
        self.mode = mode
        
        super.init(frame: CGRect.zero)

        createViews()
        
        backgroundColor = .red
        
        setupLayout()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI
    
    private lazy var stackView: UIStackView = {
        let stackView: UIStackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        
        switch mode {
            case .large, .attachmentApproval: stackView.spacing = 10
            case .small: stackView.spacing = 5
        }
        
        return stackView
    }()
    
    private lazy var imageView: UIImageView = {
        let view: UIImageView = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.layer.minificationFilter = .trilinear
        view.layer.magnificationFilter = .trilinear
        
        return view
    }()
    
    private lazy var fileTypeImageView: UIImageView = {
        let view: UIImageView = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.minificationFilter = .trilinear
        view.layer.magnificationFilter = .trilinear
        
        return view
    }()
    
    private lazy var animatedImageView: YYAnimatedImageView = {
        let view: YYAnimatedImageView = YYAnimatedImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    lazy var videoPlayButton: UIImageView = {
        let imageView: UIImageView = UIImageView(image: UIImage(named: "CirclePlay"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        
        return imageView
    }()
    
    /// Note: This uses different assets from the `videoPlayButton` and has a 'Pause' state
    private lazy var audioPlayPauseButton: UIButton = {
        let button: UIButton = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.clipsToBounds = true
        button.setBackgroundImage(UIColor.white.toImage(), for: .normal)
        button.setBackgroundImage(UIColor.white.darken(by: 0.2).toImage(), for: .highlighted)
        button.layer.cornerRadius = 30
        
        button.addTarget(self, action: #selector(audioPlayPauseButtonPressed), for: .touchUpInside)
        
        return button
    }()
    
    private lazy var titleLabel: UILabel = {
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = labelFont()
        label.text = (formattedFileName() ?? formattedFileExtension())
        label.textColor = controlTintColor
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.isHidden = ((label.text?.count ?? 0) == 0)
        
        return label
    }()
    
    private lazy var fileSizeLabel: UILabel = {
        let fileSize: UInt = attachment.dataLength
        
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = labelFont()
        // Format string for file size label in call interstitial view.
        // Embeds: {{file size as 'N mb' or 'N kb'}}.
        label.text = String(format: "ATTACHMENT_APPROVAL_FILE_SIZE_FORMAT".localized(), OWSFormat.formatFileSize(UInt(fileSize)))
        label.textColor = controlTintColor
        label.textAlignment = .center
        
        return label
    }()
    
    // MARK: - Layout

    private func createViews() {
        if attachment.isAnimatedImage {
            createAnimatedPreview()
        } else if attachment.isImage {
            createImagePreview()
        } else if attachment.isVideo {
            createVideoPreview()
        } else if attachment.isAudio {
            createAudioPreview()
        } else if attachment.isUrl {
            createUrlPreview()
        } else if attachment.isText {
            // Do nothing as we will just put the text in the 'message' input
        } else {
            createGenericPreview()
        }
    }
    
    private func setupLayout() {
        // Bottom inset
    }

    // TODO: Any reason for not just using UIStackView
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
                subview.autoPinEdge(.top, to: .bottom, of: lastView!, withOffset: 10)
            }

            lastView = subview
        }

        lastView?.autoPinEdge(toSuperviewEdge: .bottom)

        return stackView
    }
    
    private func wrapViewsInHorizontalStack(subviews: [UIView]) -> UIView {
        assert(subviews.count > 0)

        let stackView = UIView()

        var lastView: UIView?
        for subview in subviews {

            stackView.addSubview(subview)
            subview.autoVCenterInSuperview()

            if lastView == nil {
                subview.autoPinEdge(toSuperviewEdge: .left)
            } else {
                subview.autoPinEdge(.left, to: .right, of: lastView!, withOffset: 10)
            }

            lastView = subview
        }

        lastView?.autoPinEdge(toSuperviewEdge: .right)

        return stackView
    }

//    private func stackSpacing() -> CGFloat {
//        switch mode {
//        case .large, .attachmentApproval:
//            return CGFloat(10)
//        case .small:
//            return CGFloat(5)
//        }
//    }

    private func createAudioPreview() {
        guard let dataUrl = attachment.dataUrl else {
            createGenericPreview()
            return
        }

        audioPlayer = OWSAudioPlayer(mediaUrl: dataUrl, audioBehavior: .playback, delegate: self)
        
        imageView.image = UIImage(named: "FileLarge")
        fileTypeImageView.image = UIImage(named: "table_ic_notification_sound")
        setAudioIconToPlay()
        
        self.addSubview(stackView)
        self.addSubview(audioPlayPauseButton)
        
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(UIView.vSpacer(0))
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(fileSizeLabel)
        
        imageView.addSubview(fileTypeImageView)

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: widthAnchor),
            stackView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
            
            imageView.widthAnchor.constraint(equalToConstant: 150),
            imageView.heightAnchor.constraint(equalToConstant: 150),
            titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -(32 * 2)),
            fileSizeLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -(32 * 2)),
            
            fileTypeImageView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fileTypeImageView.centerYAnchor.constraint(
                equalTo: imageView.centerYAnchor,
                constant: 25
            ),
            fileTypeImageView.widthAnchor.constraint(
                equalTo: fileTypeImageView.heightAnchor,
                multiplier: ((fileTypeImageView.image?.size.width ?? 1) / (fileTypeImageView.image?.size.height ?? 1))
            ),
            fileTypeImageView.widthAnchor.constraint(
                equalTo: imageView.widthAnchor, constant: -75
            ),
            
            audioPlayPauseButton.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            audioPlayPauseButton.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            audioPlayPauseButton.widthAnchor.constraint(
                equalToConstant: (audioPlayPauseButton.layer.cornerRadius * 2)
            ),
            audioPlayPauseButton.heightAnchor.constraint(
                equalToConstant: (audioPlayPauseButton.layer.cornerRadius * 2)
            )
        ])
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
        animatedImageView.image = image
        let aspectRatio: CGFloat = (image.size.width / image.size.height)
        let clampedRatio: CGFloat = CGFloatClamp(aspectRatio, 0.05, 95.0)
        
        addSubview(animatedImageView)
//        addSubviewWithScaleAspectFitLayout(view: animatedImageView, aspectRatio: aspectRatio)
        contentView = animatedImageView
        
        NSLayoutConstraint.activate([
            animatedImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            animatedImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            animatedImageView.widthAnchor.constraint(
                equalTo: animatedImageView.heightAnchor,
                multiplier: clampedRatio
            ),
            animatedImageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            animatedImageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor)
        ])
    }

//    private func addSubviewWithScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) {
//        self.addSubview(view)
//        // This emulates the behavior of contentMode = .scaleAspectFit using
//        // iOS auto layout constraints.
//        //
//        // This allows ConversationInputToolbar to place the "cancel" button
//        // in the upper-right hand corner of the preview content.
//        view.autoCenterInSuperview()
//        view.autoPin(toAspectRatio: aspectRatio)
//        view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
//        view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
//    }

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

        imageView.image = image
//        imageView.layer.minificationFilter = .trilinear
//        imageView.layer.magnificationFilter = .trilinear
        
        let aspectRatio = image.size.width / image.size.height
        let clampedRatio: CGFloat = CGFloatClamp(aspectRatio, 0.05, 95.0)
        
//        addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
        contentView = imageView
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(
                equalTo: imageView.heightAnchor,
                multiplier: clampedRatio
            ),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor)
        ])
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

//        let imageView = UIImageView(image: image)
        imageView.image = image
//        imageView.layer.minificationFilter = .trilinear
//        imageView.layer.magnificationFilter = .trilinear
        self.addSubview(imageView)
        
        let aspectRatio = image.size.width / image.size.height
        let clampedRatio: CGFloat = CGFloatClamp(aspectRatio, 0.05, 95.0)
        
//        addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
        contentView = imageView
        
        // Attachment approval provides it's own play button to keep it
        // at the proper zoom scale.
        if mode != .attachmentApproval {
            self.addSubview(videoPlayButton)
        }
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(
                equalTo: imageView.heightAnchor,
                multiplier: clampedRatio
            ),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor)
        ])

        // Attachment approval provides it's own play button to keep it
        // at the proper zoom scale.
        if mode != .attachmentApproval {
            self.addSubview(videoPlayButton)
//            videoPlayButton.autoCenterInSuperview()
//            videoPlayButton.autoSetDimension(.width, toSize: 72)
//            videoPlayButton.autoSetDimension(.height, toSize: 72)
            
            NSLayoutConstraint.activate([
                videoPlayButton.centerXAnchor.constraint(equalTo: centerXAnchor),
                videoPlayButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 72),
                imageView.heightAnchor.constraint(equalToConstant: 72)
            ])
        }
    }
    
    private func createUrlPreview() {
        // If link previews aren't enabled then use a fallback state
        guard let linkPreviewURL: String = OWSLinkPreview.previewURL(forRawBodyText: attachment.text()) else {
//            "vc_share_link_previews_disabled_title" = "Link Previews Disabled";
//            "vc_share_link_previews_disabled_explanation" = "Enabling link previews will show previews for URLs you sshare. This can be useful, but Session will need to contact linked websites to generate previews. You can enable link previews in Session's settings.";
// TODO: Show "warning" about disabled link previews instead
            createGenericPreview()
            return
        }
        
        linkPreviewInfo = (url: linkPreviewURL, draft: nil)
        
        var subviews = [UIView]()
        
        let color: UIColor = isLightMode ? .black : .white
        let loadingView = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: color, padding: nil)
        loadingView.set(.width, to: 24)
        loadingView.set(.height, to: 24)
        loadingView.startAnimating()
        subviews.append(loadingView)
        
        let imageViewContainer = UIView()
        imageViewContainer.clipsToBounds = true
        imageViewContainer.contentMode = .center
        imageViewContainer.alpha = 0
        imageViewContainer.layer.cornerRadius = 8
        subviews.append(imageViewContainer)
        
        let imageView = createHeroImageView(imageName: "FileLarge")
        imageViewContainer.addSubview(imageView)
        imageView.pin(to: imageViewContainer)

        let titleLabel = UILabel()
        titleLabel.text = linkPreviewURL
        titleLabel.textColor = controlTintColor
        titleLabel.font = labelFont()
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subviews.append(titleLabel)
        
        let stackView = wrapViewsInVerticalStack(subviews: subviews)
        self.addSubview(stackView)
        
        titleLabel.autoPinWidthToSuperview(withMargin: 32)
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        // Build the link preview
        OWSLinkPreview.tryToBuildPreviewInfo(previewUrl: linkPreviewURL).done { [weak self] draft in
            // Loader
            loadingView.alpha = 0
            loadingView.stopAnimating()
            
            self?.linkPreviewInfo = (url: linkPreviewURL, draft: draft)
            
            // TODO: Look at refactoring this behaviour to consolidate attachment mutations
            self?.attachment.linkPreviewDraft = draft
            
            let image: UIImage?

            if let jpegImageData: Data = draft.jpegImageData, let loadedImage: UIImage = UIImage(data: jpegImageData) {
                image = loadedImage
                imageView.contentMode = .scaleAspectFill
            }
            else {
                image = UIImage(named: "Link")?.withTint(isLightMode ? .black : .white)
                imageView.contentMode = .center
            }
            
            // Image view
            (imageView as? UIImageView)?.image = image
            imageViewContainer.alpha = 1
            imageViewContainer.backgroundColor = isDarkMode ? .black : UIColor.black.withAlphaComponent(0.06)
            
            // Title
            if let title = draft.title {
                titleLabel.font = .boldSystemFont(ofSize: Values.smallFontSize)
                titleLabel.text = title
                titleLabel.textAlignment = .left
                titleLabel.numberOfLines = 2
            }
            
            guard let hStackView = self?.wrapViewsInHorizontalStack(subviews: subviews) else {
                // TODO: Fallback
                return
            }
            stackView.removeFromSuperview()
            self?.addSubview(hStackView)
            
            // We want to center the stackView in it's superview while also ensuring
            // it's superview is big enough to contain it.
            hStackView.autoPinWidthToSuperview(withMargin: 32)
            hStackView.autoVCenterInSuperview()
            NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultLow) {
                hStackView.autoPinHeightToSuperview()
            }
            hStackView.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
            hStackView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0, relation: .greaterThanOrEqual)
        }.catch { _ in
            // TODO: Fallback
            loadingView.stopAnimating()
        }.retainUntilComplete()

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

    private func createGenericPreview() {
        imageView.image = UIImage(named: "FileLarge")
        stackView.backgroundColor = .green
        self.addSubview(stackView)
        
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(UIView.vSpacer(0))
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(fileSizeLabel)
        
        imageView.addSubview(fileTypeImageView)

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: widthAnchor),
            stackView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
            
            imageView.widthAnchor.constraint(equalToConstant: 150),
            imageView.heightAnchor.constraint(equalToConstant: 150),
            titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -(32 * 2)),
            fileSizeLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -(32 * 2)),
            
            fileTypeImageView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fileTypeImageView.centerYAnchor.constraint(
                equalTo: imageView.centerYAnchor,
                constant: 25
            ),
            fileTypeImageView.widthAnchor.constraint(
                equalTo: fileTypeImageView.heightAnchor,
                multiplier: ((fileTypeImageView.image?.size.width ?? 1) / (fileTypeImageView.image?.size.height ?? 1))
            ),
            fileTypeImageView.widthAnchor.constraint(
                equalTo: imageView.widthAnchor, constant: -75
            )
        ])
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
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
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
            return Colors.accent
        case .attachmentApproval:
            return Colors.text
        }
    }

    private func formattedFileExtension() -> String? {
        guard let fileExtension = attachment.fileExtension else {
            return nil
        }

        //"Format string for file extension label in call interstitial view"
        return String(format: "ATTACHMENT_APPROVAL_FILE_EXTENSION_FORMAT".localized(), fileExtension.uppercased())
    }

    public func formattedFileName() -> String? {
        guard let sourceFilename = attachment.sourceFilename else { return nil }
        
        let filename = sourceFilename.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        guard filename.count > 0 else { return nil }
        
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

    @objc func audioPlayPauseButtonPressed(sender: UIButton) {
        audioPlayer?.togglePlayState()
    }

    // MARK: - OWSAudioPlayerDelegate

    public func audioPlaybackState() -> AudioPlaybackState {
        return playbackState
    }

    public func setAudioPlaybackState(_ value: AudioPlaybackState) {
        playbackState = value
    }
    
    public func showInvalidAudioFileAlert() {
        OWSAlerts.showErrorAlert(message: NSLocalizedString("INVALID_AUDIO_FILE_ALERT_ERROR_MESSAGE", comment: "Message for the alert indicating that an audio file is invalid."))
    }

    public func audioPlayerDidFinishPlaying(_ player: OWSAudioPlayer, successfully flag: Bool) {
        // Do nothing
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
        //attachment_audio
//        let image = UIImage(named: "audio_play_black_large")?.withRenderingMode(.alwaysTemplate)
//        assert(image != nil)
//        audioPlayButton?.setImage(image, for: .normal)
//        audioPlayButton?.imageView?.tintColor = controlTintColor
        //let image = UIImage(named: "CirclePlay")
        let image = UIImage(named: "Play")
        audioPlayPauseButton.setImage(image, for: .normal)
    }

    private func setAudioIconToPause() {
//        let image = UIImage(named: "audio_pause_black_large")?.withRenderingMode(.alwaysTemplate)
//        assert(image != nil)
//        audioPlayButton?.setImage(image, for: .normal)
//        audioPlayButton?.imageView?.tintColor = controlTintColor
        let image = UIImage(named: "Pause")
        audioPlayPauseButton.setImage(image, for: .normal)
    }
}
