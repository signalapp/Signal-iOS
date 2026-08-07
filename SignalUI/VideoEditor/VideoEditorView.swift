//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Photos
import SignalServiceKit
import UIKit

protocol VideoEditorViewDelegate: AnyObject {
    func videoEditorViewPlaybackTimeDidChange(_ videoEditorView: VideoEditorView)
}

protocol VideoEditorViewControllerProviding: AnyObject {
    func viewController(forVideoEditorView videoEditorView: VideoEditorView) -> UIViewController
}

class VideoEditorView: UIView, AttachmentPrepContentView, VideoPlaybackState, VideoPlayerViewDelegate {

    weak var delegate: VideoEditorViewDelegate?
    weak var dataSource: VideoEditorDataSource?
    weak var viewControllerProvider: VideoEditorViewControllerProviding?

    private let model: VideoEditorModel

    var isTrimmingVideo: Bool = false

    private lazy var playerView: VideoPlayerView = {
        let playerView = VideoPlayerView()
        playerView.videoPlayer = VideoPlayer(decryptedFileUrl: URL(fileURLWithPath: model.srcVideoPath))
        playerView.delegate = self
        return playerView
    }()

    private lazy var playButton: UIButton = {
        var playButtonConfig = UIButton.Configuration.roundMedia(
            image: UIImage(imageLiteralResourceName: "play-fill-40"),
            size: 72,
        )
        let playButton = UIButton(
            configuration: playButtonConfig,
            primaryAction: UIAction { [weak self] _ in
                self?.playButtonTapped()
            },
        )
        playButton.accessibilityLabel = OWSLocalizedString(
            "PLAY_BUTTON_ACCESSABILITY_LABEL",
            comment: "Accessibility label for button to start media playback",
        )
        return playButton
    }()

    init(
        model: VideoEditorModel,
        delegate: VideoEditorViewDelegate,
        dataSource: VideoEditorDataSource,
        viewControllerProvider: VideoEditorViewControllerProviding,
    ) {

        self.model = model
        self.delegate = delegate
        self.dataSource = dataSource
        self.viewControllerProvider = viewControllerProvider

        super.init(frame: .zero)

        backgroundColor = .Signal.mediaBackground
        clipsToBounds = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Views

    func configureSubviews() {
        let displaySize = model.displaySize
        let aspectRatio = displaySize.width / displaySize.height
        playerView.setContentHuggingLow()
        playerView.setCompressionResistanceLow()
        playerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapPlayerView(_:))))
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)
        // This emulates the behavior of contentMode = .scaleAspectFit using iOS auto layout constraints.
        NSLayoutConstraint.activate([
            playerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            playerView.centerYAnchor.constraint(equalTo: centerYAnchor),

            playerView.widthAnchor.constraint(equalTo: playerView.heightAnchor, multiplier: aspectRatio),
            playerView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            playerView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
        ])
        // Hug `playerView` as much as possible.
        NSLayoutConstraint.activate({
            let constraints = [
                playerView.widthAnchor.constraint(equalTo: widthAnchor),
                playerView.heightAnchor.constraint(equalTo: heightAnchor),
            ]
            constraints.forEach { $0.priority = .defaultHigh }
            return constraints
        }())
        // Preferred size.
        NSLayoutConstraint.activate({
            let constraints = [
                playerView.widthAnchor.constraint(equalToConstant: displaySize.width),
                playerView.heightAnchor.constraint(equalToConstant: displaySize.height),
            ]
            constraints.forEach { $0.priority = .defaultLow }
            return constraints
        }())

        playButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playButton)
        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
        ])

        ensureSeekReflectsTrimming()
    }

    // MARK: - Event Handlers

    @objc
    private func didTapPlayerView(_ gestureRecognizer: UIGestureRecognizer) {
        togglePlayback()
    }

    private func playButtonTapped() {
        togglePlayback()
    }

    private func togglePlayback() {
        if isPlaying {
            pauseVideo()
        } else {
            playVideo()
        }
    }

    // MARK: - Corner Radius

    private static let defaultCornerRadius: CGFloat = if #available(iOS 26, *) { 26 } else { 18 }

    private var _hasRoundedCorners: Bool = false

    var hasRoundedCorners: Bool {
        get { _hasRoundedCorners }
        set { setHasRoundedCorners(newValue, animationDuration: 0) }
    }

    func setHasRoundedCorners(_ hasRoundedCorners: Bool, animationDuration: TimeInterval) {
        guard _hasRoundedCorners != hasRoundedCorners else { return }

        _hasRoundedCorners = hasRoundedCorners
        setCornerRadius(
            hasRoundedCorners ? Self.defaultCornerRadius : 0,
            animationDuration: animationDuration,
        )
    }

    private func setCornerRadius(_ cornerRadius: CGFloat, animationDuration: TimeInterval = 0) {
        if animationDuration > 0 {
            let animation = CABasicAnimation(keyPath: #keyPath(CALayer.cornerRadius))
            animation.fromValue = layer.cornerRadius
            animation.toValue = cornerRadius
            animation.duration = animationDuration
            layer.add(animation, forKey: "cornerRadius")
        }
        layer.cornerRadius = cornerRadius
    }

    // MARK: - Video

    var trimmedStartSeconds: TimeInterval {
        return model.trimmedStartSeconds
    }

    var trimmedEndSeconds: TimeInterval {
        return model.trimmedEndSeconds
    }

    @discardableResult
    func pauseIfPlaying() -> Bool {
        guard playerView.isPlaying else {
            return false
        }
        playerView.pause()
        return true
    }

    func seek(toSeconds seconds: TimeInterval) {
        playerView.seek(to: CMTime(seconds: seconds, preferredTimescale: model.untrimmedDuration.timescale))
    }

    func playVideo() {
        if ensureSeekReflectsTrimming() {
            // If this delay isn't induced VideoPlayer.play() would reset
            // current position to 0, likely because AVPlayer hasn't yet
            // had a chance to update its currentTime.
            DispatchQueue.main.async {
                self.playerView.play()
            }
        } else {
            playerView.play()
        }
    }

    @discardableResult
    func ensureSeekReflectsTrimming() -> Bool {
        var shouldSeekToStart = false
        if currentTimeSeconds < trimmedStartSeconds {
            // If playback cursor is before the start of the clipping,
            // restart playback.
            shouldSeekToStart = true
        } else {
            // If playback cursor is very near the end of the clipping,
            // restart playback.
            let toleranceSeconds: TimeInterval = 0.1
            if currentTimeSeconds > trimmedEndSeconds - toleranceSeconds {
                shouldSeekToStart = true
            }
        }

        if shouldSeekToStart {
            seek(toSeconds: trimmedStartSeconds)
        }
        return shouldSeekToStart
    }

    private func pauseVideo() {
        playerView.pause()
    }

    private var isShowingPlayButton = true

    private func updateControls() {
        if isPlaying {
            if isShowingPlayButton {
                isShowingPlayButton = false
                UIView.animate(withDuration: 0.1) {
                    self.playButton.alpha = 0.0
                }
            }
        } else {
            if !isShowingPlayButton {
                isShowingPlayButton = true
                UIView.animate(withDuration: 0.1) {
                    self.playButton.alpha = 1.0
                }
            }
        }
    }

    // MARK: - VideoPlaybackState

    var isPlaying: Bool { playerView.isPlaying }

    var currentTimeSeconds: TimeInterval { playerView.currentTimeSeconds }

    // MARK: - VideoPlayerViewDelegate

    func videoPlayerViewStatusDidChange(_ view: VideoPlayerView) {
        updateControls()
    }

    func videoPlayerViewPlaybackTimeDidChange(_ view: VideoPlayerView) {
        // Trimming the video also changes current playback position
        // and we don't need the code below to be executed when that happens.
        guard !isTrimmingVideo else {
            return
        }

        // Prevent playback past the end of the trimming.
        guard currentTimeSeconds <= trimmedEndSeconds else {
            playerView.stop()
            return
        }

        delegate?.videoEditorViewPlaybackTimeDidChange(self)
    }
}
