//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

@objc
public class VideoPlayerView: UIView {
    @objc
    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        set {
            playerLayer.player = newValue
        }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    // Override UIView property
    override public static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
}

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
        notImplemented()
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
        notImplemented()
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)

        // Background
        backgroundColor = UIColor.lightGray.withAlphaComponent(0.5)
        if !UIAccessibilityIsReduceTransparencyEnabled() {
            addSubview(blurEffectView)
            blurEffectView.ows_autoPinToSuperviewEdges()
        }

        // Configure controls

        let kLabelFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: UIFont.Weight.regular)
        positionLabel.font = kLabelFont
        remainingLabel.font = kLabelFont

        // We use a smaller thumb for the progress slider.
        slider.setThumbImage(#imageLiteral(resourceName: "sliderProgressThumb"), for: .normal)
        slider.maximumTrackTintColor = UIColor.ows_black
        slider.minimumTrackTintColor = UIColor.ows_black

        slider.addTarget(self, action: #selector(handleSliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(handleSliderTouchUp), for: .touchUpInside)
        slider.addTarget(self, action: #selector(handleSliderTouchUp), for: .touchUpOutside)
        slider.addTarget(self, action: #selector(handleSliderValueChanged), for: .valueChanged)

        // Panning is a no-op. We just absorb pan gesture's originating in the video controls
        // from propogating so we don't inadvertently change pages while trying to scrub in
        // the MediaPageView.
        let panAbsorber = UIPanGestureRecognizer(target: self, action: nil)
        self.addGestureRecognizer(panAbsorber)

        // Layout Subviews

        addSubview(positionLabel)
        addSubview(remainingLabel)
        addSubview(slider)

        positionLabel.autoPinEdge(toSuperviewMargin: .leading)
        positionLabel.autoVCenterInSuperview()

        let kSliderMargin: CGFloat = 8

        slider.autoPinEdge(.leading, to: .trailing, of: positionLabel, withOffset: kSliderMargin)
        slider.autoVCenterInSuperview()

        remainingLabel.autoPinEdge(.leading, to: .trailing, of: slider, withOffset: kSliderMargin)
        remainingLabel.autoPinEdge(toSuperviewMargin: .trailing)
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
