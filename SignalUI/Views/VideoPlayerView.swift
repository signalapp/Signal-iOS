//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AVFoundation

@objc
public protocol VideoPlayerViewDelegate {
    func videoPlayerViewStatusDidChange(_ view: VideoPlayerView)
    func videoPlayerViewPlaybackTimeDidChange(_ view: VideoPlayerView)
}

// MARK: -

@objc
public class VideoPlayerView: UIView {

    // MARK: - Properties

    @objc
    public weak var delegate: VideoPlayerViewDelegate?

    @objc
    public var videoPlayer: OWSVideoPlayer? {
        didSet {
            player = videoPlayer?.avPlayer
        }
    }

    @objc
    override public var contentMode: UIView.ContentMode {
        didSet {
            switch contentMode {
            case .scaleAspectFill: playerLayer.videoGravity = .resizeAspectFill
            case .scaleToFill: playerLayer.videoGravity = .resize
            case .scaleAspectFit: playerLayer.videoGravity = .resizeAspect
            default: playerLayer.videoGravity = .resizeAspect
            }
        }
    }

    @objc
    public var player: AVPlayer? {
        get {
            AssertIsOnMainThread()

            return playerLayer.player
        }
        set {
            AssertIsOnMainThread()

            removeKVO(player: playerLayer.player)

            playerLayer.player = newValue

            addKVO(player: playerLayer.player)

            invalidateIntrinsicContentSize()
        }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    // Override UIView property
    override public static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    public var isPlaying: Bool {
        guard let player = player else {
            return false
        }
        return player.timeControlStatus == .playing
    }

    @objc
    public var currentTimeSeconds: Double {
        guard let videoPlayer = videoPlayer else {
            return 0
        }
        return videoPlayer.currentTimeSeconds
    }

    // MARK: - Initializers

    public init() {
        super.init(frame: .zero)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeKVO(player: player)
    }

    // MARK: -

    override public var intrinsicContentSize: CGSize {
        guard let player = self.player,
              let playerItem = player.currentItem else {
            return CGSize(square: UIView.noIntrinsicMetric)
        }

        return playerItem.asset.tracks(withMediaType: .video)
            .map { (assetTrack: AVAssetTrack) -> CGSize in
                assetTrack.naturalSize.applying(assetTrack.preferredTransform).abs
            }.reduce(.zero) {
                CGSizeMax($0, $1)
            }
    }

    // MARK: - KVO

    private var playerObservers = [NSKeyValueObservation]()
    private var periodicTimeObserver: Any?

    private func addKVO(player: AVPlayer?) {
        guard let player = player else {
            return
        }

        // Observe status changes: anything that might affect "isPlaying".
        let changeHandler = { [weak self] (_: AVPlayer, _: Any) in
            guard let self = self else { return }
            self.delegate?.videoPlayerViewStatusDidChange(self)
        }
        playerObservers = [
            player.observe(\AVPlayer.status, options: [.new, .initial], changeHandler: changeHandler),
            player.observe(\AVPlayer.timeControlStatus, options: [.new, .initial], changeHandler: changeHandler),
            player.observe(\AVPlayer.rate, options: [.new, .initial], changeHandler: changeHandler)
        ]

        // Observe playback progress.
        let interval = CMTime(seconds: 0.01, preferredTimescale: 1000)
        periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.videoPlayerViewPlaybackTimeDidChange(self)
        }
    }

    private func removeKVO(player: AVPlayer?) {
        for playerObserver in playerObservers {
            playerObserver.invalidate()
        }
        playerObservers = []

        guard let player = player else {
            return
        }
        if let periodicTimeObserver = periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil
    }

    // MARK: - Playback

    @objc
    public func pause() {
        guard let videoPlayer = videoPlayer else {
            owsFailDebug("Missing videoPlayer.")
            return
        }

        videoPlayer.pause()
    }

    @objc
    public func play() {
        guard let videoPlayer = videoPlayer else {
            owsFailDebug("Missing videoPlayer.")
            return
        }

        videoPlayer.play()
    }

    @objc
    public func stop() {
        guard let videoPlayer = videoPlayer else {
            owsFailDebug("Missing videoPlayer.")
            return
        }

        videoPlayer.stop()
    }

    @objc(seekToTime:)
    public func seek(to time: CMTime) {
        guard let videoPlayer = videoPlayer else {
            owsFailDebug("Missing videoPlayer.")
            return
        }

        videoPlayer.seek(to: time)
    }
}

// MARK: -

@objc
public protocol PlayerProgressBarDelegate {
    func playerProgressBarDidStartScrubbing(_ playerProgressBar: PlayerProgressBar)
    func playerProgressBar(_ playerProgressBar: PlayerProgressBar, scrubbedToTime time: CMTime)
    func playerProgressBar(_ playerProgressBar: PlayerProgressBar, didFinishScrubbingAtTime time: CMTime, shouldResumePlayback: Bool)
}

// Allows the user to tap anywhere on the slider to set it's position,
// without first having to grab the thumb.
class TrackingSlider: UISlider {

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        return true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@objc
public class PlayerProgressBar: UIView {

    @objc
    public weak var delegate: PlayerProgressBarDelegate?

    private lazy var formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second ]
        formatter.zeroFormattingBehavior = [ .pad ]

        return formatter
    }()

    // MARK: Subviews
    private let positionLabel = UILabel()
    private let remainingLabel = UILabel()
    private let slider = TrackingSlider()
    private let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
    weak private var progressObserver: AnyObject?

    private let kPreferredTimeScale: CMTimeScale = 100

    @objc
    public var player: AVPlayer? {
        didSet {
            guard let item = player?.currentItem else {
                owsFailDebug("No player item")
                return
            }

            slider.minimumValue = 0

            let duration: CMTime = item.asset.duration
            slider.maximumValue = Float(CMTimeGetSeconds(duration))

            // OPTIMIZE We need a high frequency observer for smooth slider updates,
            // but could use a much less frequent observer for label updates
            progressObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.01, preferredTimescale: kPreferredTimeScale), queue: nil, using: { [weak self] (_) in
                self?.updateState()
            }) as AnyObject
            updateState()
        }
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)

        // Background
        backgroundColor = UIColor.lightGray.withAlphaComponent(0.5)
        if !UIAccessibility.isReduceTransparencyEnabled {
            addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }

        // Configure controls

        let kLabelFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: UIFont.Weight.regular)
        positionLabel.font = kLabelFont
        remainingLabel.font = kLabelFont

        slider.semanticContentAttribute = .playback

        // We use a smaller thumb for the progress slider.
        slider.setThumbImage(#imageLiteral(resourceName: "sliderProgressThumb"), for: .normal)
        slider.maximumTrackTintColor = UIColor.ows_black
        slider.minimumTrackTintColor = UIColor.ows_black

        slider.addTarget(self, action: #selector(handleSliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(handleSliderTouchUp), for: .touchUpInside)
        slider.addTarget(self, action: #selector(handleSliderTouchUp), for: .touchUpOutside)
        slider.addTarget(self, action: #selector(handleSliderValueChanged), for: .valueChanged)

        // Panning is a no-op. We just absorb pan gesture's originating in the video controls
        // from propagating so we don't inadvertently change pages while trying to scrub in
        // the MediaPageView.
        let panAbsorber = UIPanGestureRecognizer(target: self, action: nil)
        self.addGestureRecognizer(panAbsorber)

        // Layout Subviews

        addSubview(positionLabel)
        addSubview(remainingLabel)
        addSubview(slider)

        positionLabel.autoPinEdge(toSuperviewMargin: .left)
        positionLabel.autoVCenterInSuperview()

        let kSliderMargin: CGFloat = 8

        slider.autoPinEdge(.left, to: .right, of: positionLabel, withOffset: kSliderMargin)
        slider.autoVCenterInSuperview()

        remainingLabel.autoPinEdge(.left, to: .right, of: slider, withOffset: kSliderMargin)
        remainingLabel.autoPinEdge(toSuperviewMargin: .right)
        remainingLabel.autoVCenterInSuperview()
    }

    // MARK: Gesture handling

    var wasPlayingWhenScrubbingStarted: Bool = false

    @objc
    private func handleSliderTouchDown(_ slider: UISlider) {
        guard let player = self.player else {
            owsFailDebug("player was nil")
            return
        }

        self.wasPlayingWhenScrubbingStarted = (player.rate != 0) && (player.error == nil)

        self.delegate?.playerProgressBarDidStartScrubbing(self)
    }

    @objc
    private func handleSliderTouchUp(_ slider: UISlider) {
        let sliderTime = time(slider: slider)
        self.delegate?.playerProgressBar(self, didFinishScrubbingAtTime: sliderTime, shouldResumePlayback: wasPlayingWhenScrubbingStarted)
    }

    @objc
    private func handleSliderValueChanged(_ slider: UISlider) {
        let sliderTime = time(slider: slider)
        self.delegate?.playerProgressBar(self, scrubbedToTime: sliderTime)
    }

    // MARK: Render cycle

    private func updateState() {
        guard let player = player else {
            owsFailDebug("player isn't set.")
            return
        }

        guard let item = player.currentItem else {
            owsFailDebug("player has no item.")
            return
        }

        let position = player.currentTime()
        let positionSeconds: Float64 = CMTimeGetSeconds(position)
        positionLabel.text = formatter.string(from: positionSeconds)

        let duration: CMTime = item.asset.duration
        let remainingTime = duration - position
        let remainingSeconds = CMTimeGetSeconds(remainingTime)

        guard let remainingString = formatter.string(from: remainingSeconds) else {
            owsFailDebug("unable to format time remaining")
            remainingLabel.text = "0:00"
            return
        }

        // show remaining time as negative
        remainingLabel.text = "-\(remainingString)"

        slider.setValue(Float(positionSeconds), animated: false)
    }

    // MARK: Util

    private func time(slider: UISlider) -> CMTime {
        let seconds: Double = Double(slider.value)
        return CMTime(seconds: seconds, preferredTimescale: kPreferredTimeScale)
    }
}
