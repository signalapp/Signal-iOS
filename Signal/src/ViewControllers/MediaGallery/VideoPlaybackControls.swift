//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CoreMedia
import SignalServiceKit
import SignalUI
import UIKit

class VideoPlaybackControlView: UIView, VideoPlaybackStatusObserver {

    // MARK: Subviews

    private let buttonStack: UIStackView = {
        let buttonStack = UIStackView(arrangedSubviews: [])
        buttonStack.alignment = .center
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.semanticContentAttribute = .forceLeftToRight
        buttonStack.spacing = 24
        return buttonStack
    }()

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
        return button
    }()

    private lazy var buttonFastForward: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "video_forward_15"), for: .normal)
        button.addTarget(self, action: #selector(didTapFastForward), for: .touchUpInside)
        return button
    }()

    // MARK: UIView

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Order must match default value of `isLandscapeLayout`.
        let buttons = [ buttonRewind, buttonPlay, buttonPause, buttonFastForward ]
        buttons.forEach { button in
            button.contentEdgeInsets = UIEdgeInsets(margin: 8)
            button.autoPin(toAspectRatio: 1)
        }
        buttonStack.addArrangedSubviews(buttons)
        addSubview(buttonStack)
        buttonStack.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public

    var isLandscapeLayout: Bool = false {
        didSet {
            updateButtonOrdering()
        }
    }

    func updateWithMediaItem(_ mediaItem: MediaGalleryItem) {
        self.mediaItem = mediaItem

        if let videoDuration = mediaItem.attachmentStream.videoDuration as? TimeInterval {
            showRewindAndFastForward = videoDuration >= 30
        } else {
            showRewindAndFastForward = false

            VideoDurationHelper.shared.promisedDuration(attachment: mediaItem.attachmentStream).observe { [weak self] result in
                guard let self, self.mediaItem == mediaItem, case .success(let duration) = result else { return }
                self.showRewindAndFastForward = duration >= 30
            }
        }
    }

    // MARK: Helpers

    private var mediaItem: MediaGalleryItem?

    var videoPlayer: VideoPlayer? {
        didSet {
            updatePlayPauseStatus()
        }
    }

    private var showRewindAndFastForward = true {
        didSet {
            buttonRewind.isHidden = !showRewindAndFastForward
            buttonFastForward.isHidden = !showRewindAndFastForward
        }
    }

    private func updateButtonOrdering() {
        buttonStack.removeArrangedSubview(buttonRewind)
        if isLandscapeLayout {
            buttonStack.insertArrangedSubview(buttonRewind, at: 2) // after Play and Pause
        } else {
            buttonStack.insertArrangedSubview(buttonRewind, at: 0)
        }
   }

    private func updatePlayPauseStatus() {
        guard let videoPlayer else { return }

        let isPlaying = videoPlayer.isPlaying
        buttonPlay.isHiddenInStackView = isPlaying
        buttonPause.isHiddenInStackView = !isPlaying
    }

    // MARK: Actions

    @objc
    private func didTapPlay() {
        videoPlayer?.play()
    }

    @objc
    private func didTapPause() {
        videoPlayer?.pause()
    }

    @objc
    private func didTapRewind() {
        videoPlayer?.rewind(15)
    }

    @objc
    private func didTapFastForward() {
        videoPlayer?.fastForward(15)
    }

    // MARK: VideoPlaybackStatusObserver

    private weak var videoPlaybackStatusProvider: VideoPlaybackStatusProvider?

    func registerWithVideoPlaybackStatusProvider(_ provider: VideoPlaybackStatusProvider?) {
        if let videoPlaybackStatusProvider {
            videoPlaybackStatusProvider.videoPlaybackStatusObserver = nil
        }

        videoPlaybackStatusProvider = provider

        if let videoPlaybackStatusProvider {
            videoPlaybackStatusProvider.videoPlaybackStatusObserver = self
        }
    }

    func videoPlayerStatusChanged(_ videoPlayer: VideoPlayer) {
        updatePlayPauseStatus()
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

    // MARK: UIView

    init(forVerticallyCompactLayout compactLayout: Bool) {
        super.init(frame: .zero)

        semanticContentAttribute = .forceLeftToRight
        preservesSuperviewLayoutMargins = true

        addSubview(slider)
        addSubview(positionLabel)
        addSubview(remainingLabel)

        // Layout
        positionLabel.autoPinEdge(toSuperviewEdge: .leading)
        remainingLabel.autoPinEdge(toSuperviewEdge: .trailing)
        if compactLayout {
            // |[X:XX] ========================= [X:XX]|
            positionLabel.autoVCenterInSuperview()
            remainingLabel.autoVCenterInSuperview()
            slider.autoAlignAxis(.horizontal, toSameAxisOf: positionLabel, withOffset: -CGHairlineWidth())

            slider.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
            positionLabel.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
            remainingLabel.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)

            slider.autoPinEdge(.leading, to: .trailing, of: positionLabel, withOffset: 12)
            slider.autoPinEdge(.trailing, to: .leading, of: remainingLabel, withOffset: -12)
        } else {
            // |=======================================|
            // |[X:XX]                           [X:XX]|
            slider.autoPinEdge(toSuperviewEdge: .top)

            positionLabel.autoPinEdge(toSuperviewEdge: .bottom)
            positionLabel.autoPinEdge(.top, to: .bottom, of: slider, withOffset: 6)

            remainingLabel.autoPinEdge(toSuperviewEdge: .bottom)
            remainingLabel.autoPinEdge(.top, to: .bottom, of: slider, withOffset: 6)

            remainingLabel.autoPinEdge(.leading, to: .trailing, of: positionLabel, withOffset: 8, relation: .greaterThanOrEqual)

            slider.autoPinEdge(.leading, to: .leading, of: positionLabel, withOffset: 2)
            slider.autoPinEdge(.trailing, to: .trailing, of: remainingLabel, withOffset: -2)
        }

        // Panning is a no-op. We just absorb pan gesture's originating in the video controls
        // from propagating so we don't inadvertently change pages while trying to scrub in
        // the MediaPageView.
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: nil))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        // This will make PlayerProgressView use all available width in a stack view.
        return CGSize(width: UIScreen.main.bounds.width, height: UIView.noIntrinsicMetric)
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
