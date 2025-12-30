//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CoreMedia
import SignalServiceKit
import SignalUI

protocol VideoPlaybackControlViewDelegate: AnyObject {
    // Single Actions
    func videoPlaybackControlViewDidTapPlayPause(_ videoPlaybackControlView: VideoPlaybackControlView)
    func videoPlaybackControlViewDidTapRewind(_ videoPlaybackControlView: VideoPlaybackControlView, duration: TimeInterval)
    func videoPlaybackControlViewDidTapFastForward(_ videoPlaybackControlView: VideoPlaybackControlView, duration: TimeInterval)

    // Continuous Actions
    func videoPlaybackControlViewDidStartRewind(_ videoPlaybackControlView: VideoPlaybackControlView)
    func videoPlaybackControlViewDidStartFastForward(_ videoPlaybackControlView: VideoPlaybackControlView)
    func videoPlaybackControlViewDidStopRewindOrFastForward(_ videoPlaybackControlView: VideoPlaybackControlView)
}

class VideoPlaybackControlView: UIView {

    // MARK: Subviews

    private func titleForRewindAndFFBUttons() -> NSAttributedString {
        let string = NumberFormatter.localizedString(
            from: Int(Self.rewindAndFastForwardSkipDuration) as NSNumber,
            number: .decimal,
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        return NSAttributedString(string: string, attributes: [
            .kern: -1,
            .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .paragraphStyle: paragraphStyle,
        ])
    }

    // Size must match same constant in `MediaControlPanelView`.
    private static let buttonContentInset: CGFloat = if #available(iOS 26, *) { 10 } else { 8 }

    private lazy var buttonPlay: UIButton = {
        let button = UIButton(configuration: .plain(), primaryAction: UIAction { [weak self] _ in
            self?.didTapPlay()
        })
        button.configuration?.image = .init(imageLiteralResourceName: "play-fill")
        button.configuration?.contentInsets = .init(margin: Self.buttonContentInset)
        button.setContentHuggingHigh()
        button.setCompressionResistanceHigh()
        return button
    }()

    private lazy var buttonPause: UIButton = {
        let button = UIButton(configuration: .plain(), primaryAction: UIAction { [weak self] _ in
            self?.didTapPause()
        })
        button.configuration?.image = .init(imageLiteralResourceName: "pause-fill")
        button.configuration?.contentInsets = .init(margin: Self.buttonContentInset)
        button.setContentHuggingHigh()
        button.setCompressionResistanceHigh()
        return button
    }()

    private lazy var buttonRewind: UIButton = {
        let button = RewindAndFFButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "skip-backward"), for: .normal)
        button.setAttributedTitle(titleForRewindAndFFBUttons(), for: .normal)
        button.addAction(UIAction { [weak self] _ in self?.didTapRewind() }, for: .touchDown)
        button.addAction(UIAction { [weak self] _ in self?.didReleaseRewind() }, for: .touchUpInside)
        button.addAction(UIAction { [weak self] _ in self?.didCancelRewindOrFF() }, for: [.touchCancel, .touchUpOutside])
        return button
    }()

    private lazy var buttonFastForward: UIButton = {
        let button = RewindAndFFButton(type: .system)
        button.setImage(.init(imageLiteralResourceName: "skip-forward"), for: .normal)
        button.setAttributedTitle(titleForRewindAndFFBUttons(), for: .normal)
        button.addAction(UIAction { [weak self] _ in self?.didTapFastForward() }, for: .touchDown)
        button.addAction(UIAction { [weak self] _ in self?.didReleaseFastForward() }, for: .touchUpInside)
        button.addAction(UIAction { [weak self] _ in self?.didCancelRewindOrFF() }, for: [.touchCancel, .touchUpOutside])
        return button
    }()

    private var glassBackgroundView: UIVisualEffectView?

    @available(iOS 26, *)
    private func glassEffect() -> UIVisualEffect? {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        return glassEffect
    }

    // MARK: UIView

    override init(frame: CGRect) {
        super.init(frame: frame)

        semanticContentAttribute = .playback

        let selfOrVisualEffectContentView: UIView

        // Glass background.
        if #available(iOS 26, *) {
            let glassEffectView = UIVisualEffectView(effect: glassEffect())
            glassEffectView.clipsToBounds = true
            glassEffectView.cornerConfiguration = .capsule()
            glassEffectView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glassEffectView)
            NSLayoutConstraint.activate([
                glassEffectView.topAnchor.constraint(equalTo: topAnchor),
                glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            selfOrVisualEffectContentView = glassEffectView.contentView
            glassBackgroundView = glassEffectView
        } else {
            selfOrVisualEffectContentView = self
        }

        let buttons = [buttonRewind, buttonPlay, buttonPause, buttonFastForward]
        buttons.forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            selfOrVisualEffectContentView.addSubview(button)
        }

        // Default state for Play / Pause
        buttonPlay.isHidden = isVideoPlaying
        buttonPause.isHidden = !isVideoPlaying
        buttonRewind.isHidden = true
        buttonFastForward.isHidden = true

        // Permanent layout constraints.
        NSLayoutConstraint.activate([
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
            buttonFastForward.widthAnchor.constraint(equalTo: buttonFastForward.heightAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConstraints() {
        super.updateConstraints()
        if let buttonLayoutConstraints {
            NSLayoutConstraint.deactivate(buttonLayoutConstraints)
        }
        let constraints = layoutConstraintsForCurrentConfiguration()
        NSLayoutConstraint.activate(constraints)
        buttonLayoutConstraints = constraints
    }

    // MARK: Public

    weak var delegate: VideoPlaybackControlViewDelegate?

    func updateWithMediaItem(_ mediaItem: MediaGalleryItem) {
        switch mediaItem.attachmentStream.attachmentStream.contentType {
        case .video(let videoDuration, _, _):
            updateDuration(videoDuration)
        default:
            let attachmentStream = mediaItem.attachmentStream.attachmentStream
            switch attachmentStream.contentType {
            case .file, .invalid, .image, .animatedImage, .audio:
                break
            case .video(let duration, _, _):
                updateDuration(duration)
            }
        }
    }

    private func updateDuration(_ duration: TimeInterval) {
        let durationThreshold: TimeInterval = 30
        showRewindAndFastForward = duration >= durationThreshold
    }

    private var isVideoPlaying = false
    private var animatePlayPauseTransition = false
    private var playPauseButtonAnimator: UIViewPropertyAnimator?

    func updateStatusWithPlayer(_ videoPlayer: VideoPlayer) {
        let isPlaying = videoPlayer.isPlaying

        guard isVideoPlaying != isPlaying else { return }

        isVideoPlaying = isPlaying

        // Only user-initiated playback state changes cause animated Play/Pause transition.
        guard animatePlayPauseTransition else {
            // Do nothing if there is an active animation in progress.
            // Playback status will be refreshed upon animation completion.
            if playPauseButtonAnimator == nil {
                buttonPlay.isHidden = isPlaying
                buttonPause.isHidden = !isPlaying
            }
            return
        }

        // User might tap Play/Pause again before animation completes.
        // In that case previous animations are stopped and are replaced by new animations.
        if let playPauseButtonAnimator {
            playPauseButtonAnimator.stopAnimation(true)
            self.playPauseButtonAnimator = nil
        }

        let fromButton: UIButton // button that is currently visible, reflecting opposite to `isPlaying`
        let fromButtonTransform: CGAffineTransform
        let toButton: UIButton // button that should reflect `isPlaying` upon animation completion
        let toButtonTransform: CGAffineTransform
        if isPlaying {
            fromButton = buttonPlay
            fromButtonTransform = .scale(0.1).rotated(by: 0.5 * .pi)
            toButton = buttonPause
            toButtonTransform = .scale(0.1).rotated(by: -0.5 * .pi)
        } else {
            fromButton = buttonPause
            fromButtonTransform = .scale(0.1).rotated(by: -0.5 * .pi)
            toButton = buttonPlay
            toButtonTransform = .scale(0.1).rotated(by: 0.5 * .pi)
        }
        // Prepare initial state for appearing button
        toButton.isHidden = false
        toButton.alpha = 0
        toButton.transform = toButtonTransform

        let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 0.7, springResponse: 0.3)
        animator.addAnimations {
            toButton.alpha = 1
            toButton.transform = .identity
        }
        animator.addAnimations {
            fromButton.alpha = 0
            fromButton.transform = fromButtonTransform
        }
        animator.addCompletion { [weak self] _ in
            fromButton.isHidden = true
            fromButton.alpha = 1
            fromButton.transform = .identity

            self?.playPauseButtonAnimator = nil
            self?.updateStatusWithPlayer(videoPlayer)
        }
        animator.startAnimation()

        playPauseButtonAnimator = animator
        animatePlayPauseTransition = false
    }

    // MARK: Animations

    private var viewsForOpacityAnimation: [UIView] {
        [buttonRewind, buttonPlay, buttonPause, buttonFastForward].filter { $0.isHidden == false }
    }

    func prepareToBeAnimatedIn() {
        if #available(iOS 26, *), let glassBackgroundView {
            glassBackgroundView.effect = nil
        }
        viewsForOpacityAnimation.forEach { $0.alpha = 0 }
        isHidden = false
    }

    func animateIn() {
        if #available(iOS 26, *), let glassBackgroundView {
            glassBackgroundView.effect = glassEffect()
        }
        viewsForOpacityAnimation.forEach { $0.alpha = 1 }
    }

    func animateOut() {
        if #available(iOS 26, *), let glassBackgroundView {
            glassBackgroundView.effect = nil
        }
        viewsForOpacityAnimation.forEach { $0.alpha = 0 }
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

    private static let horizontalMargin: CGFloat = 6
    private static let buttonSpacing: CGFloat = 12

    private func layoutConstraintsForCurrentConfiguration() -> [NSLayoutConstraint] {
        guard showRewindAndFastForward else {
            // |[Play]|
            return [
                buttonPlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                buttonPlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            ]
        }

        // |[Rewind] [Play] [FastF]|
        return [
            buttonRewind.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalMargin),
            buttonPlay.leadingAnchor.constraint(equalTo: buttonRewind.trailingAnchor, constant: Self.buttonSpacing),
            buttonFastForward.leadingAnchor.constraint(equalTo: buttonPlay.trailingAnchor, constant: Self.buttonSpacing),
            buttonFastForward.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalMargin),
        ]
    }

    private var tapAndHoldTimer: Timer?
    private var isRewindInProgress = false
    private var isFastForwardInProgress = false
    private static let rewindAndFastForwardSkipDuration: TimeInterval = 15

    private func startContinuousRewind() {
        guard !isRewindInProgress, !isFastForwardInProgress else { return }

        let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 0.7, springResponse: 0.3)
        animator.addAnimations {
            self.buttonRewind.transform = .rotate(-0.5 * .pi)
        }
        animator.startAnimation()

        isRewindInProgress = true
        delegate?.videoPlaybackControlViewDidStartRewind(self)
    }

    private func startContinuousFastForward() {
        guard !isRewindInProgress, !isFastForwardInProgress else { return }

        let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 0.7, springResponse: 0.3)
        animator.addAnimations {
            self.buttonFastForward.transform = .rotate(0.5 * .pi)
        }
        animator.startAnimation()

        isFastForwardInProgress = true
        delegate?.videoPlaybackControlViewDidStartFastForward(self)
    }

    private func stopContinuousRewindOrFastForward() {
        guard isRewindInProgress || isFastForwardInProgress else { return }

        let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 0.7, springResponse: 0.3)
        if isRewindInProgress {
            animator.addAnimations {
                self.buttonRewind.transform = .identity
            }
            isRewindInProgress = false
        }
        if isFastForwardInProgress {
            animator.addAnimations {
                self.buttonFastForward.transform = .identity
            }
            isFastForwardInProgress = false
        }
        animator.startAnimation()

        delegate?.videoPlaybackControlViewDidStopRewindOrFastForward(self)
    }

    // MARK: Actions

    private func didTapPlay() {
        guard !isRewindInProgress, !isFastForwardInProgress else { return }

        animatePlayPauseTransition = true
        delegate?.videoPlaybackControlViewDidTapPlayPause(self)
    }

    private func didTapPause() {
        guard !isRewindInProgress, !isFastForwardInProgress else { return }

        animatePlayPauseTransition = true
        delegate?.videoPlaybackControlViewDidTapPlayPause(self)
    }

    private func didTapRewind() {
        guard !isRewindInProgress, !isFastForwardInProgress, tapAndHoldTimer == nil else { return }

        tapAndHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false, block: { [weak self] timer in
            guard let self else { return }
            self.startContinuousRewind()
            self.tapAndHoldTimer = nil
        })
    }

    private func didReleaseRewind() {
        // Timer not yet fired - single tap.
        if let tapAndHoldTimer {
            tapAndHoldTimer.invalidate()
            self.tapAndHoldTimer = nil
            delegate?.videoPlaybackControlViewDidTapRewind(self, duration: Self.rewindAndFastForwardSkipDuration)
            return
        }
        stopContinuousRewindOrFastForward()
    }

    private func didTapFastForward() {
        guard !isRewindInProgress, !isFastForwardInProgress, tapAndHoldTimer == nil else { return }

        tapAndHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false, block: { [weak self] timer in
            guard let self else { return }
            self.startContinuousFastForward()
            self.tapAndHoldTimer = nil
        })
    }

    private func didReleaseFastForward() {
        // Timer not yet fired - single tap.
        if let tapAndHoldTimer {
            tapAndHoldTimer.invalidate()
            self.tapAndHoldTimer = nil
            delegate?.videoPlaybackControlViewDidTapFastForward(self, duration: Self.rewindAndFastForwardSkipDuration)
            return
        }
        stopContinuousRewindOrFastForward()
    }

    private func didCancelRewindOrFF() {
        if let tapAndHoldTimer {
            tapAndHoldTimer.invalidate()
            self.tapAndHoldTimer = nil
        }
        stopContinuousRewindOrFastForward()
    }

    private class RewindAndFFButton: UIButton {

        override func layoutSubviews() {
            super.layoutSubviews()
            if let titleLabel, let imageView {
                imageView.center = bounds.center
                titleLabel.bounds = imageView.bounds
                titleLabel.center = imageView.center.offsetBy(dx: -1)
            }
        }
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
            slider.maximumValue = max(0.01, Float(CMTimeGetSeconds(item.asset.duration)))

            progressObserver = avPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1 / 60, preferredTimescale: Self.preferredTimeScale),
                queue: nil,
                using: { [weak self] _ in
                    self?.updateState()
                },
            ) as AnyObject

            updateState()
        }
    }

    private var _hasGlassBackground: Bool = true

    @available(iOS 26, *)
    var hasGlassBackground: Bool {
        get { _hasGlassBackground }
        set {
            _hasGlassBackground = newValue
            updateBackground()
        }
    }

    private func createLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        label.textColor = .Signal.label
        label.setContentHuggingHorizontalHigh()
        label.setCompressionResistanceHorizontalHigh()
        return label
    }

    private lazy var positionLabel = createLabel()
    private lazy var remainingLabel = createLabel()

    private lazy var slider: UISlider = {
        let slider = VideoPlaybackSlider()
        slider.semanticContentAttribute = .playback
        slider.setThumbImage(UIImage(), for: .normal)
        slider.setThumbImage(UIImage(), for: .highlighted)
        slider.minimumTrackTintColor = .Signal.label
        slider.maximumTrackTintColor = .Signal.quaternaryLabel
        slider.addAction(UIAction { [weak self] _ in self?.handleSliderTouchDown() }, for: .touchDown)
        slider.addAction(UIAction { [weak self] _ in self?.handleSliderTouchUp() }, for: [.touchUpInside, .touchUpOutside])
        slider.addAction(UIAction { [weak self] _ in self?.handleSliderValueChanged() }, for: .valueChanged)
        return slider
    }()

    // Glass on iOS 26, `nil` otherwise.
    private var glassBackgroundView: UIVisualEffectView?

    @available(iOS 26, *)
    private func interactiveGlassEffect() -> UIVisualEffect? {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        return glassEffect
    }

    private weak var progressObserver: AnyObject?

    private static let preferredTimeScale: CMTimeScale = 100

    // MARK: UIView

    init() {
        super.init(frame: .zero)

        semanticContentAttribute = .forceLeftToRight

        let selfOrVisualEffectContentView: UIView
        if #available(iOS 26, *) {
            let glassEffectView = UIVisualEffectView(effect: interactiveGlassEffect())
            glassEffectView.translatesAutoresizingMaskIntoConstraints = false
            glassEffectView.clipsToBounds = true
            glassEffectView.cornerConfiguration = .capsule()
            addSubview(glassEffectView)
            NSLayoutConstraint.activate([
                glassEffectView.topAnchor.constraint(equalTo: topAnchor),
                glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            selfOrVisualEffectContentView = glassEffectView.contentView
            glassBackgroundView = glassEffectView
        } else {
            selfOrVisualEffectContentView = self
        }

        slider.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        remainingLabel.translatesAutoresizingMaskIntoConstraints = false

        selfOrVisualEffectContentView.addSubview(slider)
        selfOrVisualEffectContentView.addSubview(positionLabel)
        selfOrVisualEffectContentView.addSubview(remainingLabel)

        // |[X:XX] ========================= [X:XX]|

        // Extra margin on iOS 26 because of the glass background.
        let hMargin: CGFloat = if #available(iOS 26, *) { 16 } else { 0 }
        let height: CGFloat = if #available(iOS 26, *) { 44 } else { 36 }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),

            positionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hMargin),
            positionLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            slider.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: positionLabel.trailingAnchor, constant: 12),
            slider.trailingAnchor.constraint(equalTo: remainingLabel.leadingAnchor, constant: -12),

            remainingLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            remainingLabel.centerYAnchor.constraint(equalTo: positionLabel.centerYAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hMargin),
        ])

        // Panning is a no-op. We just absorb pan gesture's originating in the video controls
        // from propagating so we don't inadvertently change pages while trying to scrub in
        // the MediaPageView.
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: nil))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS 26, *)
    private func updateBackground() {
        if hasGlassBackground {
            if let glassBackgroundView, glassBackgroundView.effect == nil {
                glassBackgroundView.effect = interactiveGlassEffect()
            }
        } else {
            if let glassBackgroundView {
                glassBackgroundView.effect = nil
            }
        }
    }

    // MARK: Animations

    private var viewsForOpacityAnimation: [UIView] {
        [positionLabel, slider, remainingLabel]
    }

    func prepareToBeAnimatedIn() {
        if #available(iOS 26, *), let glassBackgroundView, hasGlassBackground {
            glassBackgroundView.effect = nil
        }
        viewsForOpacityAnimation.forEach { $0.alpha = 0 }
        isHidden = false
    }

    func animateIn() {
        if #available(iOS 26, *), let glassBackgroundView, hasGlassBackground {
            glassBackgroundView.effect = interactiveGlassEffect()
        }
        viewsForOpacityAnimation.forEach { $0.alpha = 1 }
    }

    func animateOut() {
        if #available(iOS 26, *), let glassBackgroundView, hasGlassBackground {
            glassBackgroundView.effect = nil
        }
        viewsForOpacityAnimation.forEach { $0.alpha = 0 }
    }

    // MARK: Slider Handling

    private var wasPlayingWhenScrubbingStarted: Bool = false

    private func time(slider: UISlider) -> CMTime {
        return CMTime(seconds: Double(slider.value), preferredTimescale: Self.preferredTimeScale)
    }

    private func handleSliderTouchDown() {
        guard let videoPlayer else {
            owsFailBeta("player is nil")
            return
        }
        wasPlayingWhenScrubbingStarted = videoPlayer.isPlaying
        videoPlayer.pause()
    }

    private func handleSliderTouchUp() {
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

    private func handleSliderValueChanged() {
        guard let videoPlayer else {
            owsFailBeta("player is nil")
            return
        }
        let sliderTime = time(slider: slider)
        videoPlayer.seek(to: sliderTime)
    }

    // MARK: Render cycle

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
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
        positionLabel.text = Self.formatter.string(from: position.seconds)
        slider.setValue(Float(position.seconds), animated: false)

        let timeRangeRemaining = CMTimeRange(start: avPlayer.currentTime(), duration: item.asset.duration)
        guard timeRangeRemaining.isValid, let remainingString = Self.formatter.string(from: timeRangeRemaining.duration.seconds) else {
            owsFailDebug("unable to format time remaining")
            remainingLabel.text = "0:00"
            return
        }

        // show remaining time as negative
        remainingLabel.text = "-\(remainingString)"
    }

    // Overriden to allow to set custom track height.
    private class VideoPlaybackSlider: UISlider {
        private static let trackHeight: CGFloat = 10

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: Self.trackHeight)
        }

        override func trackRect(forBounds bounds: CGRect) -> CGRect {
            var rect = super.trackRect(forBounds: bounds)
            rect.size.height = Self.trackHeight
            rect.origin.y = (bounds.height - Self.trackHeight) / 2
            return rect
        }
    }
}
