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
            case .attachmentApproval: stackView.spacing = 2
            case .large: stackView.spacing = 10
            case .small: stackView.spacing = 5
        }
        
        return stackView
    }()
    
    private lazy var loadingView: NVActivityIndicatorView = {
        let view: NVActivityIndicatorView = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: Colors.text, padding: nil)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        
        return view
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
        button.addTarget(self, action: #selector(audioPlayPauseButtonPressed), for: .touchUpInside)
        
        return button
    }()
    
    private lazy var titleLabel: UILabel = {
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        
        if let fileName: String = attachment.sourceFilename?.trimmingCharacters(in: .whitespacesAndNewlines), fileName.count > 0 {
            label.text = fileName
        }
        else if let fileExtension: String = attachment.fileExtension {
            label.text = String(
                format: "ATTACHMENT_APPROVAL_FILE_EXTENSION_FORMAT".localized(),
                fileExtension.uppercased()
            )
        }
        
        label.isHidden = ((label.text?.count ?? 0) == 0)
        
        switch mode {
            case .attachmentApproval:
                label.font = UIFont.ows_boldFont(withSize: ScaleFromIPhone5To7Plus(16, 22))
                label.textColor = Colors.text
                
            case .large:
                label.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(18, 24))
                label.textColor = Colors.accent
                
            case .small:
                label.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(14, 14))
                label.textColor = Colors.accent
        }
        
        return label
    }()
    
    private lazy var fileSizeLabel: UILabel = {
        let fileSize: UInt = attachment.dataLength
        
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // Format string for file size label in call interstitial view.
        // Embeds: {{file size as 'N mb' or 'N kb'}}.
        label.text = String(format: "ATTACHMENT_APPROVAL_FILE_SIZE_FORMAT".localized(), OWSFormat.formatFileSize(UInt(fileSize)))
        label.textAlignment = .center
        
        switch mode {
            case .attachmentApproval:
                label.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(12, 18))
                label.textColor = Colors.pinIcon
                
            case .large:
                label.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(18, 24))
                label.textColor = Colors.accent
                
            case .small:
                label.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(14, 14))
                label.textColor = Colors.accent
        }
        
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
        
        imageView.image = UIImage(named: "FileLarge")?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = Colors.text
        fileTypeImageView.image = UIImage(named: "table_ic_notification_sound")?
            .withRenderingMode(.alwaysTemplate)
        fileTypeImageView.tintColor = Colors.text
        setAudioIconToPlay()
        
        self.addSubview(stackView)
        self.addSubview(audioPlayPauseButton)
        
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(UIView.vSpacer(0))
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(fileSizeLabel)
        
        imageView.addSubview(fileTypeImageView)
        
        let imageSize: CGFloat = {
            switch mode {
                case .large: return 200
                case .attachmentApproval: return 150
                case .small: return 80
            }
        }()
        let audioButtonSize: CGFloat = (imageSize / 2.5)
        audioPlayPauseButton.layer.cornerRadius = (audioButtonSize / 2)
        
        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: widthAnchor),
            stackView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
            
            imageView.widthAnchor.constraint(equalToConstant: imageSize),
            imageView.heightAnchor.constraint(equalToConstant: imageSize),
            titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -(32 * 2)),
            fileSizeLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -(32 * 2)),
            
            fileTypeImageView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fileTypeImageView.centerYAnchor.constraint(
                equalTo: imageView.centerYAnchor,
                constant: ceil(imageSize * 0.15)
            ),
            fileTypeImageView.widthAnchor.constraint(
                equalTo: fileTypeImageView.heightAnchor,
                multiplier: ((fileTypeImageView.image?.size.width ?? 1) / (fileTypeImageView.image?.size.height ?? 1))
            ),
            fileTypeImageView.widthAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 0.5),
            
            audioPlayPauseButton.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            audioPlayPauseButton.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            audioPlayPauseButton.widthAnchor.constraint(equalToConstant: audioButtonSize),
            audioPlayPauseButton.heightAnchor.constraint(equalToConstant: audioButtonSize)
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

        imageView.image = image
        self.addSubview(imageView)
        
        let aspectRatio = image.size.width / image.size.height
        let clampedRatio: CGFloat = CGFloatClamp(aspectRatio, 0.05, 95.0)
        
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
            titleLabel.text = "vc_share_link_previews_disabled_title".localized()
            titleLabel.isHidden = false
            
            fileSizeLabel.text = "vc_share_link_previews_disabled_explanation".localized()
            fileSizeLabel.textColor = Colors.text
            fileSizeLabel.numberOfLines = 0
            
            self.addSubview(stackView)
            
            stackView.addArrangedSubview(titleLabel)
            stackView.addArrangedSubview(UIView.vSpacer(10))
            stackView.addArrangedSubview(fileSizeLabel)
            
            NSLayoutConstraint.activate([
                stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
                stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
                stackView.widthAnchor.constraint(equalTo: widthAnchor, constant: -(32 * 2)),
                stackView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor)
            ])
            return
        }
        
        linkPreviewInfo = (url: linkPreviewURL, draft: nil)

        stackView.axis = .horizontal
        stackView.distribution = .fill
        
        imageView.clipsToBounds = true
        imageView.image = UIImage(named: "Link")?.withTint(Colors.text)
        imageView.alpha = 0 // Not 'isHidden' because we want it to take up space in the UIStackView
        imageView.contentMode = .center
        imageView.backgroundColor = (isDarkMode ? .black : UIColor.black.withAlphaComponent(0.06))
        imageView.layer.cornerRadius = 8
        
        loadingView.isHidden = false
        loadingView.startAnimating()
        
        titleLabel.font = .boldSystemFont(ofSize: Values.smallFontSize)
        titleLabel.text = linkPreviewURL
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 2
        titleLabel.isHidden = false
        
        self.addSubview(stackView)
        self.addSubview(loadingView)
        
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(UIView.vhSpacer(10, 0))
        stackView.addArrangedSubview(titleLabel)
        
        let imageSize: CGFloat = {
            switch mode {
                case .large: return 120
                case .attachmentApproval, .small: return 80
            }
        }()
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: widthAnchor, constant: -(32 * 2)),
            stackView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
            
            imageView.widthAnchor.constraint(equalToConstant: imageSize),
            imageView.heightAnchor.constraint(equalToConstant: imageSize),
            
            loadingView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            loadingView.widthAnchor.constraint(equalToConstant: ceil(imageSize / 3)),
            loadingView.heightAnchor.constraint(equalToConstant: ceil(imageSize / 3))
        ])
        
        // Build the link preview
        OWSLinkPreview.tryToBuildPreviewInfo(previewUrl: linkPreviewURL)
            .done { [weak self] draft in
                // TODO: Look at refactoring this behaviour to consolidate attachment mutations
                self?.attachment.linkPreviewDraft = draft
                self?.linkPreviewInfo = (url: linkPreviewURL, draft: draft)
                
                // Update the UI
                self?.titleLabel.text = (draft.title ?? self?.titleLabel.text)
                self?.loadingView.alpha = 0
                self?.loadingView.stopAnimating()
                self?.imageView.alpha = 1
                
                if let jpegImageData: Data = draft.jpegImageData, let loadedImage: UIImage = UIImage(data: jpegImageData) {
                    self?.imageView.image = loadedImage
                    self?.imageView.contentMode = .scaleAspectFill
                }
            }
            .catch { [weak self] _ in
                self?.titleLabel.attributedText = NSMutableAttributedString(string: linkPreviewURL)
                    .rtlSafeAppend(
                        "\n\("vc_share_link_previews_error".localized())",
                        attributes: [
                            NSAttributedString.Key.font: UIFont.ows_regularFont(
                                withSize: Values.verySmallFontSize
                            ),
                            NSAttributedString.Key.foregroundColor: self?.fileSizeLabel.textColor
                        ]
                        .compactMapValues { $0 }
                    )
                self?.loadingView.alpha = 0
                self?.loadingView.stopAnimating()
                self?.imageView.alpha = 1
            }
            .retainUntilComplete()
    }

    private func createGenericPreview() {
        imageView.image = UIImage(named: "FileLarge")
        
        self.addSubview(stackView)
        
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(UIView.vSpacer(5))
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(fileSizeLabel)
        
        imageView.addSubview(fileTypeImageView)
        
        let imageSize: CGFloat = {
            switch mode {
                case .large: return 200
                case .attachmentApproval: return 150
                case .small: return 80
            }
        }()

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: widthAnchor),
            stackView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
            
            imageView.widthAnchor.constraint(equalToConstant: imageSize),
            imageView.heightAnchor.constraint(equalToConstant: imageSize),
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
        switch playbackState {
            case .playing: setAudioIconToPause()
            default: setAudioIconToPlay()
        }
    }

    public func setAudioProgress(_ progress: CGFloat, duration: CGFloat) {
        audioProgressSeconds = progress
        audioDurationSeconds = duration
    }

    private func setAudioIconToPlay() {
        audioPlayPauseButton.setImage(UIImage(named: "Play"), for: .normal)
    }

    private func setAudioIconToPause() {
        audioPlayPauseButton.setImage(UIImage(named: "Pause"), for: .normal)
    }
}
