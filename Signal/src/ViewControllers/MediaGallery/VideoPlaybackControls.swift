//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CoreMedia
import SignalServiceKit
import SignalUI

protocol VideoPlaybackControlViewDelegate: AnyObject {
    func videoPlaybackControlViewDidTapPlayPause(_ videoPlaybackControlView: VideoPlaybackControlView)
    func videoPlaybackControlViewDidTapRewind(_ videoPlaybackControlView: VideoPlaybackControlView)
    func videoPlaybackControlViewDidTapFastForward(_ videoPlaybackControlView: VideoPlaybackControlView)
}

class VideoPlaybackControlView: UIView {

    // MARK: Subviews

    private lazy var buttonPlay: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "play-solid-24"), for: .normal)
        button.addTarget(self, action: #selector(didTapPlay), for: .touchUpInside)
        return button
    }()

    private lazy var buttonPause: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "pause-filled-24"), for: .normal)
        button.addTarget(self, action: #selector(didTapPause), for: .touchUpInside)
        return button
    }()

    private lazy var buttonRewind: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "video_rewind_15"), for: .normal)
        button.addTarget(self, action: #selector(didTapRewind), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var buttonFastForward: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "video_forward_15"), for: .normal)
        button.addTarget(self, action: #selector(didTapFastForward), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    // MARK: UIView

    override init(frame: CGRect) {
        super.init(frame: frame)

        semanticContentAttribute = .forceLeftToRight

        // Order must match default value of `isLandscapeLayout`.
        let buttons = [ buttonRewind, buttonPlay, buttonPause, buttonFastForward ]
        buttons.forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            button.contentEdgeInsets = UIEdgeInsets(margin: 8)
            addSubview(button)
        }

        // Permanent layout constraints.
        addConstraints([
            buttonPlay.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonPlay.topAnchor.constraint(equalTo: topAnchor),
            buttonPlay.heightAnchor.constraint(equalTo: buttonPlay.widthAnchor),

            buttonPause.centerXAnchor.constraint(equalTo: buttonPlay.centerXAnchor),
            buttonPause.centerYAnchor.constraint(equalTo: buttonPlay.centerYAnchor),
            buttonPause.heightAnchor.constraint(equalTo: buttonPlay.heightAnchor),
            buttonPause.widthAnchor.constraint(equalTo: buttonPause.heightAnchor),

            buttonRewind.centerYAnchor.constraint(equalTo: buttonPlay.centerYAnchor),
            buttonRewind.heightAnchor.constraint(equalTo: buttonPlay.heightAnchor),
            buttonRewind.widthAnchor.constraint(equalTo: buttonRewind.heightAnchor),

            buttonFastForward.centerYAnchor.constraint(equalTo: buttonPlay.centerYAnchor),
            buttonFastForward.heightAnchor.constraint(equalTo: buttonPlay.heightAnchor),
            buttonFastForward.widthAnchor.constraint(equalTo: buttonFastForward.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConstraints() {
        super.updateConstraints()
        if let buttonLayoutConstraints {
            removeConstraints(buttonLayoutConstraints)
        }
        let constraints = layoutConstraintsForCurrentConfiguration()
        addConstraints(constraints)
        buttonLayoutConstraints = constraints
    }

    // MARK: Public

    var isLandscapeLayout: Bool = false {
        didSet {
            guard oldValue != isLandscapeLayout else { return }
            setNeedsUpdateConstraints()
        }
    }

    weak var delegate: VideoPlaybackControlViewDelegate?

    func updateWithMediaItem(_ mediaItem: MediaGalleryItem) {
        let durationThreshold: TimeInterval = 30
        if let videoDuration = mediaItem.attachmentStream.videoDuration as? TimeInterval {
            showRewindAndFastForward = videoDuration >= durationThreshold
        } else {
            showRewindAndFastForward = false
            self.mediaItem = mediaItem

            VideoDurationHelper.shared.promisedDuration(attachment: mediaItem.attachmentStream).observe { [weak self] result in
                guard let self, self.mediaItem === mediaItem, case .success(let duration) = result else {
                    self?.mediaItem = nil
                    return
                }
                self.showRewindAndFastForward = duration >= durationThreshold

                // Only hold on to mediaItem for as long as it is necessary.
                self.mediaItem = nil
            }
        }
    }

    func updateStatusWithPlayer(_ videoPlayer: VideoPlayer) {
        let isPlaying = videoPlayer.isPlaying
        buttonPlay.isHidden = isPlaying
        buttonPause.isHidden = !isPlaying
    }

    // MARK: Helpers

    private var mediaItem: MediaGalleryItem?

    private var showRewindAndFastForward = false {
        didSet {
            guard oldValue != showRewindAndFastForward else { return }
            buttonRewind.isHidden = !showRewindAndFastForward
            buttonFastForward.isHidden = !showRewindAndFastForward
            setNeedsUpdateConstraints()
        }
    }

    private var buttonLayoutConstraints: [NSLayoutConstraint]?

    private func layoutConstraintsForCurrentConfiguration() -> [NSLayoutConstraint] {
        guard showRewindAndFastForward else {
            // |[Play]|
            return [
                buttonPlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                buttonPlay.trailingAnchor.constraint(equalTo: trailingAnchor)
            ]
        }

        if isLandscapeLayout {
            let buttonSpacing: CGFloat = 14
            // |[Play] [Rewind] [FastF]|
            return [
                buttonPlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                buttonRewind.leadingAnchor.constraint(equalTo: buttonPlay.trailingAnchor, constant: buttonSpacing),
                buttonFastForward.leadingAnchor.constraint(equalTo: buttonRewind.trailingAnchor, constant: buttonSpacing),
                buttonFastForward.trailingAnchor.constraint(equalTo: trailingAnchor)
            ]
        } else {
            let buttonSpacing: CGFloat = 24
            // |[Rewind] [Play] [FastF]|
            return [
                buttonRewind.leadingAnchor.constraint(equalTo: leadingAnchor),
                buttonPlay.leadingAnchor.constraint(equalTo: buttonRewind.trailingAnchor, constant: buttonSpacing),
                buttonFastForward.leadingAnchor.constraint(equalTo: buttonPlay.trailingAnchor, constant: buttonSpacing),
                buttonFastForward.trailingAnchor.constraint(equalTo: trailingAnchor)
            ]
        }
    }

    // MARK: Actions

    @objc
    private func didTapPlay() {
        delegate?.videoPlaybackControlViewDidTapPlayPause(self)
    }

    @objc
    private func didTapPause() {
        delegate?.videoPlaybackControlViewDidTapPlayPause(self)
    }

    @objc
    private func didTapRewind() {
        delegate?.videoPlaybackControlViewDidTapRewind(self)
    }

    @objc
    private func didTapFastForward() {
        delegate?.videoPlaybackControlViewDidTapFastForward(self)
    }
}

protocol PlayerProgressViewDelegate: AnyObject {
    func playerProgressViewDidStartScrubbing(_ playerProgressBar: PlayerProgressView)
    func playerProgressView(_ playerProgressView: PlayerProgressView, scrubbedToTime time: CMTime)
    func playerProgressView(_ playerProgressView: PlayerProgressView, didFinishScrubbingAtTime time: CMTime, shouldResumePlayback: Bool)
}

class PlayerProgressView: UIView {

    weak var delegate: PlayerProgressViewDelegate?

    var videoPlayer: VideoPlayer? {
        willSet {
            if let avPlayer = videoPlayer?.avPlayer, let progressObserver {
                avPlayer.removeTimeObserver(progressObserver)
                self.progressObserver = nil
            }
        }
        didSet {
            guard let avPlayer = videoPlayer?.avPlayer else { return }

            guard let item = avPlayer.currentItem else {
                owsFailDebug("No player item")
                return
            }

            slider.minimumValue = 0
            slider.maximumValue = Float(CMTimeGetSeconds(item.asset.duration))

            progressObserver = avPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1/60, preferredTimescale: Self.preferredTimeScale),
                queue: nil,
                using: { [weak self] (_) in
                    self?.updateState()
                }
            ) as AnyObject

            updateState()
        }
    }

    private func createLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .ows_whiteAlpha80
        label.setContentHuggingHorizontalHigh()
        label.setCompressionResistanceHorizontalHigh()
        return label
    }
    private lazy var positionLabel = createLabel()
    private lazy var remainingLabel = createLabel()

    private lazy var slider: UISlider = {
        let slider = TrackingSlider()
        slider.semanticContentAttribute = .playback
        slider.setThumbImage(#imageLiteral(resourceName: "sliderProgressThumb"), for: .normal)
        slider.maximumTrackTintColor = .ows_whiteAlpha20
        slider.minimumTrackTintColor = .ows_whiteAlpha20
        slider.addTarget(self, action: #selector(handleSliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(handleSliderTouchUp), for: [ .touchUpInside, .touchUpOutside ])
        slider.addTarget(self, action: #selector(handleSliderValueChanged), for: .valueChanged)
        return slider
    }()

    private weak var progressObserver: AnyObject?

    private static let preferredTimeScale: CMTimeScale = 100

    var isVerticallyCompactLayout: Bool {
        didSet {
            if isVerticallyCompactLayout {
                removeConstraints(normalLayoutConstraints)
                addConstraints(compactLayoutConstraints)
            } else {
                removeConstraints(compactLayoutConstraints)
                addConstraints(normalLayoutConstraints)
            }
        }
    }

    private var compactLayoutConstraints = [NSLayoutConstraint]()
    private var normalLayoutConstraints = [NSLayoutConstraint]()

    // MARK: UIView

    init(forVerticallyCompactLayout compactLayout: Bool) {
        isVerticallyCompactLayout = compactLayout

        super.init(frame: .zero)

        semanticContentAttribute = .forceLeftToRight
        preservesSuperviewLayoutMargins = true

        addSubview(slider)
        addSubview(positionLabel)
        addSubview(remainingLabel)

        // Layout
        positionLabel.autoPinEdge(toSuperviewEdge: .leading)
        remainingLabel.autoPinEdge(toSuperviewEdge: .trailing)
        slider.autoSetDimension(.height, toSize: 35)

        // Compact Layout (landscape screen orientation).
        // |[X:XX] ========================= [X:XX]|
        compactLayoutConstraints = [
            positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            remainingLabel.centerYAnchor.constraint(equalTo: positionLabel.centerYAnchor),
            slider.centerYAnchor.constraint(equalTo: positionLabel.centerYAnchor, constant: -CGHairlineWidth()),

            positionLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            remainingLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            slider.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),

            slider.leadingAnchor.constraint(equalTo: positionLabel.trailingAnchor, constant: 12),
            slider.trailingAnchor.constraint(equalTo: remainingLabel.leadingAnchor, constant: -12)
        ]

        // Two-row layout (portrait screen orientation).
        // |=======================================|
        // |[X:XX]                           [X:XX]|
        normalLayoutConstraints = [
            slider.topAnchor.constraint(equalTo: topAnchor),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),

            positionLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 1),
            positionLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            remainingLabel.centerYAnchor.constraint(equalTo: positionLabel.centerYAnchor),
            remainingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: positionLabel.trailingAnchor, constant: 8)
        ]

        if isVerticallyCompactLayout {
            addConstraints(compactLayoutConstraints)
        } else {
            addConstraints(normalLayoutConstraints)
        }

        // Panning is a no-op. We just absorb pan gesture's originating in the video controls
        // from propagating so we don't inadvertently change pages while trying to scrub in
        // the MediaPageView.
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: nil))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Slider Handling

    private var wasPlayingWhenScrubbingStarted: Bool = false

    private func time(slider: UISlider) -> CMTime {
        return CMTime(seconds: Double(slider.value), preferredTimescale: Self.preferredTimeScale)
    }

    @objc
    private func handleSliderTouchDown(_ slider: UISlider) {
        guard let videoPlayer else {
            owsFailBeta("player is nil")
            return
        }
        wasPlayingWhenScrubbingStarted = videoPlayer.isPlaying
        videoPlayer.pause()
    }

    @objc
    private func handleSliderTouchUp(_ slider: UISlider) {
        guard let videoPlayer else {
            owsFailBeta("player is nil")
            return
        }
        let sliderTime = time(slider: slider)
        videoPlayer.seek(to: sliderTime)
        if wasPlayingWhenScrubbingStarted {
            videoPlayer.play()
        }
    }

    @objc
    private func handleSliderValueChanged(_ slider: UISlider) {
        guard let videoPlayer else {
            owsFailBeta("player is nil")
            return
        }
        let sliderTime = time(slider: slider)
        videoPlayer.seek(to: sliderTime)
    }

    // MARK: Render cycle

    private static var formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second ]
        formatter.zeroFormattingBehavior = [ .pad ]
        return formatter
    }()

    private func updateState() {
        guard let avPlayer = videoPlayer?.avPlayer else {
            owsFailDebug("player isn't set.")
            return
        }

        guard let item = avPlayer.currentItem else {
            owsFailDebug("player has no item.")
            return
        }

        let position = avPlayer.currentTime()
        let positionSeconds: Float64 = CMTimeGetSeconds(position)
        positionLabel.text = Self.formatter.string(from: positionSeconds)

        let duration: CMTime = item.asset.duration
        let remainingTime = duration - position
        let remainingSeconds = CMTimeGetSeconds(remainingTime)

        guard let remainingString = Self.formatter.string(from: remainingSeconds) else {
            owsFailDebug("unable to format time remaining")
            remainingLabel.text = "0:00"
            return
        }

        // show remaining time as negative
        remainingLabel.text = "-\(remainingString)"

        slider.setValue(Float(positionSeconds), animated: false)
    }

    // Allows the user to tap anywhere on the slider to set it's position,
    // without first having to grab the thumb.
    private class TrackingSlider: UISlider {

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            return true
        }
    }
}
