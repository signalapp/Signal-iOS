//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit
import YYImage

class MediaMessageView: AttachmentPrepContentView, OWSAudioPlayerDelegate {

    private let attachment: SignalAttachment

    private var audioPlayer: OWSAudioPlayer?
    private lazy var audioPlayButton = UIButton()

    // MARK: Initializers

    required init(attachment: SignalAttachment) {
        assert(!attachment.hasError)
        self.attachment = attachment

        super.init(frame: CGRect.zero)

        tintColor = .white

        createViews()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Create Views

    private func createViews() {
        if attachment.isLoopingVideo {
            createLoopingVideoPreview()
        } else if attachment.isAnimatedImage {
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
        let stackView = UIStackView(arrangedSubviews: subviews)
        stackView.spacing = 10
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }

    private func createAudioPreview() {
        guard let dataUrl = attachment.dataUrl else {
            createGenericPreview()
            return
        }

        let audioPlayer = OWSAudioPlayer(mediaUrl: dataUrl, audioBehavior: .playback)
        audioPlayer.delegate = self
        self.audioPlayer = audioPlayer

        var subviews = [UIView]()

        setAudioIconToPlay()
        audioPlayButton.imageView?.layer.minificationFilter = .trilinear
        audioPlayButton.imageView?.layer.magnificationFilter = .trilinear
        audioPlayButton.addTarget(self, action: #selector(audioPlayButtonPressed), for: .touchUpInside)
        let buttonSize = createHeroViewSize
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
        addSubview(stackView)

        stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor).isActive = true
        stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor).isActive = true
        stackView.topAnchor.constraint(greaterThanOrEqualTo: contentLayoutGuide.topAnchor).isActive = true
        stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.bottomAnchor).isActive = true
    }

    private func createLoopingVideoPreview() {
        guard let url = attachment.dataUrl,
              let video = LoopingVideo(url: url),
              let previewImage = attachment.videoPreview() else {
            createGenericPreview()
            return
        }

        let loopingVideoView = LoopingVideoView()
        loopingVideoView.video = video
        addSubviewWithScaleAspectFitLayout(view: loopingVideoView, aspectRatio: previewImage.size.aspectRatio)
    }

    private func createAnimatedPreview() {
        guard attachment.isValidImage,
              let dataUrl = attachment.dataUrl,
              let image = YYImage(contentsOfFile: dataUrl.path),
              image.size.width > 0 && image.size.height > 0 else {
            createGenericPreview()
            return
        }

        let animatedImageView = YYAnimatedImageView()
        animatedImageView.image = image
        let aspectRatio = image.size.width / image.size.height
        addSubviewWithScaleAspectFitLayout(view: animatedImageView, aspectRatio: aspectRatio)
    }

    private func addSubviewWithScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) {
        addSubview(view)

        // This emulates the behavior of contentMode = .scaleAspectFit using iOS auto layout constraints.
        view.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor).isActive = true
        view.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor).isActive = true
        view.autoPin(toAspectRatio: aspectRatio)
        view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
        view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
    }

    private func createImagePreview() {
        guard attachment.isValidImage,
              let image = attachment.image(),
              image.size.width > 0 && image.size.height > 0 else {
            createGenericPreview()
            return
        }

        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        let aspectRatio = image.size.width / image.size.height
        addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
    }

    private func createVideoPreview() {
        guard attachment.isValidVideo,
              let image = attachment.videoPreview(),
              image.size.width > 0 && image.size.height > 0 else {
            createGenericPreview()
            return
        }

        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        let aspectRatio = image.size.width / image.size.height
        addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
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
        addSubview(stackView)

        stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor).isActive = true
        stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor).isActive = true
        stackView.topAnchor.constraint(greaterThanOrEqualTo: contentLayoutGuide.topAnchor).isActive = true
        stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.bottomAnchor).isActive = true
    }

    private var createHeroViewSize: CGFloat {
        ScaleFromIPhone5(100)
    }

    private func createHeroImageView(imageName: String) -> UIView {
        let imageSize = createHeroViewSize

        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.shadowColor = UIColor.black.cgColor
        let shadowScaling: CGFloat = 5.0
        imageView.layer.shadowRadius = CGFloat(2.0 * shadowScaling)
        imageView.layer.shadowOpacity = 0.25
        imageView.layer.shadowOffset = CGSize(square: 0.75 * shadowScaling)
        imageView.autoSetDimension(.width, toSize: imageSize)
        imageView.autoSetDimension(.height, toSize: imageSize)

        return imageView
    }

    private var labelFont: UIFont {
        UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(18, 24))
    }

    private func formattedFileExtension() -> String? {
        guard let fileExtension = attachment.fileExtension else {
            return nil
        }

        return String(format: OWSLocalizedString("ATTACHMENT_APPROVAL_FILE_EXTENSION_FORMAT",
                                               comment: "Format string for file extension label in call interstitial view"),
                      fileExtension.uppercased())
    }

    private func formattedFileName() -> String? {
        guard let sourceFilename = attachment.sourceFilename else {
            return nil
        }
        let filename = sourceFilename.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !filename.isEmpty else {
            return nil
        }
        return filename
    }

    private func createFileNameLabel() -> UIView? {
        guard let filename = formattedFileName() ?? formattedFileExtension() else {
            return nil
        }

        let label = UILabel()
        label.text = filename
        label.textColor = tintColor
        label.font = labelFont
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    private func createFileSizeLabel() -> UIView {
        let label = UILabel()
        let fileSize = attachment.dataLength
        label.text = String(format: OWSLocalizedString("ATTACHMENT_APPROVAL_FILE_SIZE_FORMAT",
                                                     comment: "Format string for file size label in call interstitial view. Embeds: {{file size as 'N mb' or 'N kb'}}."),
                            OWSFormat.localizedFileSizeString(from: Int64(fileSize)))

        label.textColor = tintColor
        label.font = labelFont
        label.textAlignment = .center
        return label
    }

    // MARK: - Event Handlers

    @objc
    private func audioPlayButtonPressed(sender: UIButton) {
        audioPlayer?.togglePlayState()
    }

    // MARK: - OWSAudioPlayerDelegate

    var audioPlaybackState = AudioPlaybackState.stopped {
        didSet {
            AssertIsOnMainThread()

            ensureButtonState()
        }
    }

    func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float) { }

    private func ensureButtonState() {
        if audioPlaybackState == .playing {
            setAudioIconToPause()
        } else {
            setAudioIconToPlay()
        }
    }

    private func setAudioIconToPlay() {
        audioPlayButton.setImage(UIImage(named: "audio_play_black_large"), for: .normal)
    }

    private func setAudioIconToPause() {
        audioPlayButton.setImage(UIImage(named: "audio_pause_black_large"), for: .normal)
    }
}
