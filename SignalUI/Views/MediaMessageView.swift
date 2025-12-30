//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SDWebImage
import SignalServiceKit
import UIKit

class MediaMessageView: UIView, AudioPlayerDelegate {

    private let attachment: PreviewableAttachment

    private var audioPlayer: AudioPlayer?
    private lazy var audioPlayButton = UIButton()

    // MARK: Initializers

    init(attachment: PreviewableAttachment, contentMode: UIView.ContentMode = .scaleAspectFit) {
        self.attachment = attachment

        super.init(frame: CGRect.zero)

        self.contentMode = contentMode
        tintColor = .white

        recreateViews()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var contentMode: UIView.ContentMode {
        get {
            return super.contentMode
        }
        set {
            switch newValue {
            case .scaleAspectFit:
                super.contentMode = .scaleAspectFit
            case .scaleAspectFill:
                super.contentMode = .scaleAspectFill
            default:
                owsFailDebug("Invalid content mode, only scale aspect fit and fill are supported")
                super.contentMode = .scaleAspectFit
            }
            recreateViews()
        }
    }

    // MARK: - Create Views

    private func recreateViews() {
        subviews.forEach { $0.removeFromSuperview() }

        if attachment.rawValue.isLoopingVideo {
            createLoopingVideoPreview()
        } else if attachment.rawValue.isAnimatedImage {
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
        let audioPlayer = AudioPlayer(attachment: attachment, audioBehavior: .playback)

        audioPlayer.delegate = self
        self.audioPlayer = audioPlayer

        var subviews = [UIView]()

        setAudioIconToPlay()
        audioPlayButton.addTarget(self, action: #selector(audioPlayButtonPressed), for: .touchUpInside)
        let buttonSize = createHeroViewSize
        audioPlayButton.autoSetDimension(.width, toSize: buttonSize)
        audioPlayButton.autoSetDimension(.height, toSize: buttonSize)
        subviews.append(audioPlayButton)

        let fileNameLabel = createFileNameLabel()
        if let fileNameLabel {
            subviews.append(fileNameLabel)
        }

        let fileSizeLabel = createFileSizeLabel()
        subviews.append(fileSizeLabel)

        let stackView = wrapViewsInVerticalStack(subviews: subviews)
        addSubview(stackView)

        stackView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        stackView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor).isActive = true
        stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor).isActive = true
    }

    private func createLoopingVideoPreview() {
        guard
            let video = LoopingVideo(attachment),
            let previewImage = attachment.rawValue.videoPreview()
        else {
            createGenericPreview()
            return
        }

        let loopingVideoView = LoopingVideoView()
        loopingVideoView.video = video
        if contentMode == .scaleAspectFill {
            addSubviewWithScaleAspectFillLayout(view: loopingVideoView, aspectRatio: previewImage.size.aspectRatio)
        } else {
            addSubviewWithScaleAspectFitLayout(view: loopingVideoView, aspectRatio: previewImage.size.aspectRatio)
        }
    }

    private func createAnimatedPreview() {
        guard
            attachment.isImage,
            let image = SDAnimatedImage(contentsOfFile: attachment.rawValue.dataSource.fileUrl.path),
            image.size.width > 0, image.size.height > 0
        else {
            createGenericPreview()
            return
        }

        let animatedImageView = SDAnimatedImageView()
        animatedImageView.image = image
        let aspectRatio = image.size.width / image.size.height

        if contentMode == .scaleAspectFill {
            addSubviewWithScaleAspectFillLayout(view: animatedImageView, aspectRatio: aspectRatio)
        } else {
            addSubviewWithScaleAspectFitLayout(view: animatedImageView, aspectRatio: aspectRatio)
        }
    }

    private func addSubviewWithScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) {
        addSubview(view)

        // This emulates the behavior of contentMode = .scaleAspectFit using iOS auto layout constraints.
        view.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        view.autoPin(toAspectRatio: aspectRatio)
        view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
        view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
    }

    private func addSubviewWithScaleAspectFillLayout(view: UIView, aspectRatio: CGFloat) {
        addSubview(view)

        // This emulates the behavior of contentMode = .scaleAspectFill using iOS auto layout constraints.
        view.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        view.autoPin(toAspectRatio: aspectRatio)
        view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .greaterThanOrEqual)
        view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .greaterThanOrEqual)
        view.autoMatch(.width, to: .height, of: self, withMultiplier: aspectRatio, relation: .lessThanOrEqual)
        view.autoMatch(.height, to: .width, of: self, withMultiplier: 1 / aspectRatio, relation: .lessThanOrEqual)
    }

    private func createImagePreview() {
        guard
            attachment.isImage,
            let image = attachment.rawValue.image(),
            image.size.width > 0, image.size.height > 0
        else {
            createGenericPreview()
            return
        }

        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        let aspectRatio = image.size.width / image.size.height
        if contentMode == .scaleAspectFill {
            addSubviewWithScaleAspectFillLayout(view: imageView, aspectRatio: aspectRatio)
        } else {
            addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
        }
    }

    private func createVideoPreview() {
        guard
            attachment.isVideo,
            let image = attachment.rawValue.videoPreview(),
            image.size.width > 0, image.size.height > 0
        else {
            createGenericPreview()
            return
        }

        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        let aspectRatio = image.size.width / image.size.height

        if contentMode == .scaleAspectFill {
            addSubviewWithScaleAspectFillLayout(view: imageView, aspectRatio: aspectRatio)
        } else {
            addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
        }
    }

    private func createGenericPreview() {
        var subviews = [UIView]()

        let imageView = createHeroImageView(imageName: "file-display")
        subviews.append(imageView)

        let fileNameLabel = createFileNameLabel()
        if let fileNameLabel {
            subviews.append(fileNameLabel)
        }

        let fileSizeLabel = createFileSizeLabel()
        subviews.append(fileSizeLabel)

        let stackView = wrapViewsInVerticalStack(subviews: subviews)
        addSubview(stackView)

        stackView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        stackView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor).isActive = true
        stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor).isActive = true
    }

    private var createHeroViewSize: CGFloat {
        .scaleFromIPhone5(100)
    }

    private func createHeroImageView(imageName: String) -> UIView {
        let imageSize = createHeroViewSize

        let imageView = UIImageView(image: UIImage(named: imageName))
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
        UIFont.regularFont(ofSize: .scaleFromIPhone5To7Plus(18, 24))
    }

    private func formattedFileExtension() -> String? {
        guard let fileExtension = attachment.rawValue.fileExtension else {
            return nil
        }

        return String(
            format: OWSLocalizedString(
                "ATTACHMENT_APPROVAL_FILE_EXTENSION_FORMAT",
                comment: "Format string for file extension label in call interstitial view",
            ),
            fileExtension.uppercased(),
        )
    }

    private func formattedFileName() -> String? {
        guard let sourceFilename = attachment.rawValue.dataSource.sourceFilename?.filterFilename() else {
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
        let fileSize = (try? attachment.rawValue.dataSource.readLength()) ?? 0
        label.text = String(
            format: OWSLocalizedString(
                "ATTACHMENT_APPROVAL_FILE_SIZE_FORMAT",
                comment: "Format string for file size label in call interstitial view. Embeds: {{file size as 'N mb' or 'N kb'}}.",
            ),
            OWSFormat.localizedFileSizeString(from: Int64(fileSize)),
        )

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

    func audioPlayerDidFinish() { }

    private func ensureButtonState() {
        if audioPlaybackState == .playing {
            setAudioIconToPause()
        } else {
            setAudioIconToPlay()
        }
    }

    private func setAudioIconToPlay() {
        audioPlayButton.setImage(UIImage(named: "play-circle-display"), for: .normal)
    }

    private func setAudioIconToPause() {
        audioPlayButton.setImage(UIImage(named: "pause-circle-display"), for: .normal)
    }
}
