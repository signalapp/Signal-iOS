//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

class AudioMessageView: ManualStackView, CVAudioPlayerListener {
    private enum Constants {
        static let animationSize: CGFloat = 40
        static let waveformHeight: CGFloat = 32
        static let progressTrackHeight: CGFloat = 4
        static let thumbSize = CGSize(width: 24, height: 18)
        static let undownloadedSliderAlpha: CGFloat = 0.5
        static let vSpacing: CGFloat = 2
        static let innerLayoutMargins = UIEdgeInsets(hMargin: 0, vMargin: 4)
    }

    // MARK: - State

    private var playbackID: CVAudioPlaybackID {
        CVAudioPlaybackID(audioAttachment: presentation.audioAttachment)
    }

    private var attachment: Attachment { presentation.audioAttachment.attachment }
    private var attachmentStream: AttachmentStream? { presentation.audioAttachment.attachmentStream?.attachmentStream }
    private var durationSeconds: TimeInterval? { presentation.audioAttachment.durationSeconds }

    private weak var audioMessageViewDelegate: AudioMessageViewDelegate?
    private let mediaCache: CVMediaCache

    private var audioPlaybackState: AudioPlaybackState {
        AppEnvironment.shared.cvAudioPlayerRef.audioPlaybackState(playbackID: playbackID)
    }

    private var elapsedSeconds: TimeInterval {
        guard attachmentStream != nil else {
            return 0
        }
        return AppEnvironment.shared.cvAudioPlayerRef.playbackProgress(playbackID: playbackID)
    }

    private var isViewed = false
    func setViewed(_ isViewed: Bool, animated: Bool) {
        guard isViewed != self.isViewed else { return }
        self.isViewed = isViewed
        updateContents(animated: animated)
    }

    // MARK: - Views

    private let playedDotAnimation: LottieAnimationView
    private let playPauseAnimation: LottieAnimationView
    private let playPauseContainer = ManualLayoutView.circleView(name: "playPauseContainer")
    private let progressSlider = ProgressSlider()
    private let waveformProgress: AudioWaveformProgressView
    private let waveformContainer = ManualLayoutView(name: "waveformContainer")
    private let presentation: AudioPresenter

    // MARK: Init

    init(
        presentation: AudioPresenter,
        audioMessageViewDelegate: AudioMessageViewDelegate,
        mediaCache: CVMediaCache,
    ) {
        self.audioMessageViewDelegate = audioMessageViewDelegate
        self.mediaCache = mediaCache

        self.waveformProgress = AudioWaveformProgressView(mediaCache: mediaCache)
        self.playedDotAnimation = mediaCache.buildLottieAnimationView(name: "audio-played-dot")
        self.playPauseAnimation = mediaCache.buildLottieAnimationView(name: "playPauseButton")
        self.presentation = presentation

        super.init(name: presentation.name)
    }

    // MARK: - Rendering

    func configureForRendering(cellMeasurement: CVCellMeasurement, conversationStyle: ConversationStyle) {
        var outerSubviews = [UIView]()

        if let topLabelConfig = presentation.topLabelConfig {
            let topLabel = CVLabel()
            topLabelConfig.applyForRendering(label: topLabel)
            outerSubviews.append(topLabel)
        }

        waveformProgress.playedColor = presentation.playedColor()
        waveformProgress.unplayedColor = presentation.unplayedColor()
        waveformProgress.thumbColor = presentation.waveformThumbColor()
        waveformProgress.waveformDidFailToLoad = { [weak self] in
            // No waveform for this audio; a progress bar is all we can show.
            self?.setWaveformVisible(false)
        }
        waveformProgress.audioWaveformTask = presentation.audioWaveform(attachment: attachment)
        setWaveformVisible(true)
        waveformContainer.addSubviewToFillSuperviewEdges(waveformProgress)

        progressSlider.setThumbImage(Self.thumbImage(color: presentation.progressBarThumbColor()), for: .normal)
        progressSlider.minimumTrackTintColor = presentation.playedColor()
        progressSlider.maximumTrackTintColor = presentation.unplayedColor()
        progressSlider.isUserInteractionEnabled = false
        // Dim the slider until the attachment is downloaded.
        progressSlider.alpha = attachmentStream != nil ? 1 : Constants.undownloadedSliderAlpha

        waveformContainer.addSubview(progressSlider) { [progressSlider] view in
            var sliderFrame = view.bounds
            sliderFrame.height = 12
            sliderFrame.y = (view.bounds.height - sliderFrame.height) * 0.5
            progressSlider.frame = sliderFrame
        }

        presentation.configureForRendering(conversationStyle: conversationStyle)

        let leftView: UIView
        switch presentation.audioAttachment.state {
        case .attachmentStream:
            let playPauseAnimation = self.playPauseAnimation
            let playedDotAnimation = self.playedDotAnimation

            // TODO: There is a bug with Lottie where animations lag when there are a lot
            // of other things happening on screen. Since this animation generally plays
            // when the progress bar / waveform is rendering we speed up the playback to
            // address some of the lag issues. Once this is fixed we should update lottie
            // and remove this check. https://github.com/airbnb/lottie-ios/issues/1034
            playPauseAnimation.animationSpeed = 3
            playPauseAnimation.backgroundBehavior = .forceFinish
            playPauseAnimation.contentMode = .scaleAspectFit

            playedDotAnimation.animationSpeed = 3
            playedDotAnimation.backgroundBehavior = .forceFinish
            playedDotAnimation.contentMode = .scaleAspectFit

            let fillColorKeypath = AnimationKeypath(keypath: "**.Fill 1.Color")
            playPauseAnimation.setValueProvider(
                ColorValueProvider(
                    presentation.playPauseAnimationColor().lottieColorValue,
                ),
                keypath: fillColorKeypath,
            )
            playedDotAnimation.setValueProvider(
                ColorValueProvider(
                    presentation.playedDotAnimationColor(
                        conversationStyle: conversationStyle,
                    ).lottieColorValue,
                ),
                keypath: fillColorKeypath,
            )

            playPauseContainer.backgroundColor = presentation.playPauseContainerBackgroundColor(
                conversationStyle: conversationStyle,
            )
            playPauseContainer.addSubviewToCenterOnSuperview(playPauseAnimation, size: CGSize(square: 24))

            presentation.playedDotContainer.addSubviewToCenterOnSuperview(playedDotAnimation, size: CGSize(square: 16))

            leftView = playPauseContainer
        case .attachmentPointer(_, let downloadState):
            leftView = CVAttachmentProgressView(
                direction: .download(
                    attachmentID: attachment.id,
                    downloadState: downloadState,
                ),
                configuration: presentation.progressViewConfiguration(
                    conversationStyle: conversationStyle,
                ),
            )
        }

        let topInnerStack = ManualStackView(name: "playerStack")
        topInnerStack.semanticContentAttribute = .playback
        topInnerStack.configure(
            config: Self.topInnerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_topInnerStack,
            subviews: [
                leftView,
                .transparentSpacer(),
                waveformContainer,
                .transparentSpacer(),
            ],
        )
        outerSubviews.append(topInnerStack)

        let generators = presentation.bottomSubviewGenerators(conversationStyle: conversationStyle)

        let bottomInnerStack = ManualStackView(name: "playbackLabelStack")
        bottomInnerStack.configure(
            config: Self.bottomInnerStackConfig(presentation: presentation),
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_bottomInnerStack,
            subviews: generators.map { $0.viewGenerator() },
        )
        outerSubviews.append(bottomInnerStack)

        self.configure(
            config: Self.outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: outerSubviews,
        )

        updateContents(animated: false)

        AppEnvironment.shared.cvAudioPlayerRef.addListener(self)
    }

    // MARK: - Measurement

    private static let measurementKey_topInnerStack = "CVComponentAudioAttachment.measurementKey_topInnerStack"
    private static let measurementKey_bottomInnerStack = "CVComponentAudioAttachment.measurementKey_bottomInnerStack"
    private static let measurementKey_outerStack = "CVComponentAudioAttachment.measurementKey_outerStack"

    static func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        presentation: AudioPresenter,
    ) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var outerSubviewInfos = [ManualStackSubviewInfo]()
        if let topLabelConfig = presentation.topLabelConfig {
            let topLabelSize = CGSize(width: 0, height: topLabelConfig.font.lineHeight)
            outerSubviewInfos.append(topLabelSize.asManualSubviewInfo)
        }

        var topInnerSubviewInfos = [ManualStackSubviewInfo]()
        let leftViewSize = CGSize(square: Constants.animationSize)
        topInnerSubviewInfos.append(leftViewSize.asManualSubviewInfo(hasFixedSize: true))

        topInnerSubviewInfos.append(CGSize(width: 12, height: 0).asManualSubviewInfo(hasFixedWidth: true))

        let waveformSize = CGSize(width: 0, height: Constants.waveformHeight)
        topInnerSubviewInfos.append(waveformSize.asManualSubviewInfo(hasFixedHeight: true))

        topInnerSubviewInfos.append(CGSize(width: 6, height: 0).asManualSubviewInfo(hasFixedWidth: true))

        let topInnerStackMeasurement = ManualStackView.measure(
            config: topInnerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_topInnerStack,
            subviewInfos: topInnerSubviewInfos,
        )
        let topInnerStackSize = topInnerStackMeasurement.measuredSize
        outerSubviewInfos.append(topInnerStackSize.ceil.asManualSubviewInfo)

        let bottomInnerStackMeasurement = ManualStackView.measure(
            config: bottomInnerStackConfig(presentation: presentation),
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_bottomInnerStack,
            subviewInfos: presentation.bottomSubviewGenerators(conversationStyle: nil).map { $0.measurementInfo(maxWidth) },
        )
        let bottomInnerStackSize = bottomInnerStackMeasurement.measuredSize
        outerSubviewInfos.append(bottomInnerStackSize.ceil.asManualSubviewInfo)

        let outerStackMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: outerSubviewInfos,
            maxWidth: maxWidth,
        )
        return outerStackMeasurement.measuredSize
    }

    // MARK: - View Configs

    private static var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .fill,
            spacing: Constants.vSpacing,
            layoutMargins: .zero,
        )
    }

    private static var topInnerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: 0,
            layoutMargins: Constants.innerLayoutMargins,
        )
    }

    private static func bottomInnerStackConfig(presentation: AudioPresenter) -> CVStackViewConfig {
        CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: presentation.bottomInnerStackSpacing,
            layoutMargins: .zero,
        )
    }

    // MARK: - Tapping

    func handleTap(sender: UIGestureRecognizer, itemModel: CVItemModel) -> Bool {
        presentation.playbackRateView.handleTap(
            sender: sender,
            itemModel: itemModel,
            audioMessageViewDelegate: audioMessageViewDelegate,
        )
    }

    // MARK: - Scrubbing

    var isScrubbing = false

    func isPointInScrubbableRegion(_ point: CGPoint) -> Bool {
        // Only downloaded audio can be scrubbed, waveform or not.
        guard attachmentStream != nil, durationSeconds != nil else {
            return false
        }

        let locationInContainer = convert(point, to: waveformContainer)
        return locationInContainer.x >= 0 && locationInContainer.x <= waveformContainer.width
    }

    func progressForLocation(_ point: CGPoint) -> CGFloat {
        let containerFrame = convert(waveformContainer.bounds, from: waveformContainer)
        let newRatio = CGFloat.inverseLerp(point.x, min: containerFrame.minX, max: containerFrame.maxX).clamp01()
        return newRatio.clamp01()
    }

    func scrubToLocation(_ point: CGPoint) -> TimeInterval {
        guard let durationSeconds else { return 0 }

        let newRatio = progressForLocation(point)
        visibleProgressRatio = newRatio
        return TimeInterval(newRatio) * durationSeconds
    }

    // MARK: - Contents

    // If set, the playback should reflect
    // this progress, not the actual progress.
    // During pan gestures, this gives a preview
    // of playback scrubbing.
    private var overrideProgress: CGFloat?

    func updateContents(animated: Bool) {
        updatePlaybackState(animated: animated)
        updateViewedState(animated: animated)
        updateAudioProgress()
        updatePlaybackRate(animated: animated)
    }

    // MARK: Progress

    private var audioProgressRatio: CGFloat {
        if let overrideProgress = self.overrideProgress {
            return overrideProgress.clamp01()
        }
        guard let durationSeconds, durationSeconds > 0 else { return 0 }
        return CGFloat(elapsedSeconds / durationSeconds)
    }

    private var visibleProgressRatio: CGFloat {
        get {
            waveformProgress.value
        }
        set {
            waveformProgress.value = newValue
            progressSlider.value = Float(newValue)
            if let durationSeconds {
                let elapsedSeconds = durationSeconds * TimeInterval(newValue)
                let timeRemaining = max(0, durationSeconds - elapsedSeconds)
                presentation.playbackTimeLabel.text = OWSFormat.localizedDurationString(from: timeRemaining)
            } else {
                presentation.playbackTimeLabel.text = OWSFormat.localizedDurationString(from: 0)
            }
        }
    }

    // MARK: Playback State

    private var playPauseAnimationTarget: AnimationProgressTime?
    private var playPauseAnimationEnd: (() -> Void)?

    private func updatePlaybackState(animated: Bool = true) {
        let isPlaying = audioPlaybackState == .playing
        let destination: AnimationProgressTime = isPlaying ? 1 : 0

        // Do nothing if we're already there.
        guard destination != playPauseAnimation.currentProgress else { return }

        // Do nothing if we are already animating.
        if
            animated,
            playPauseAnimation.isAnimationQueued || playPauseAnimation.isAnimationPlaying,
            playPauseAnimationTarget == destination
        {
            return
        }

        playPauseAnimationTarget = destination

        if animated {
            playPauseAnimationEnd?()
            let endCellAnimation = audioMessageViewDelegate?.beginCellAnimation(maximumDuration: 0.2)
            playPauseAnimationEnd = endCellAnimation
            playPauseAnimation.play(toProgress: destination) { _ in
                endCellAnimation?()
            }
        } else {
            playPauseAnimationEnd?()
            playPauseAnimation.currentProgress = destination
        }
    }

    private func updateAudioProgress() {
        guard !isScrubbing else { return }

        visibleProgressRatio = audioProgressRatio
    }

    private func setWaveformVisible(_ isVisible: Bool) {
        waveformProgress.isHidden = !isVisible
        progressSlider.isHidden = isVisible
    }

    func setOverrideProgress(_ value: CGFloat, animated: Bool) {
        overrideProgress = value
        updateContents(animated: animated)
    }

    func clearOverrideProgress(animated: Bool) {
        overrideProgress = nil
        updateContents(animated: animated)
    }

    // MARK: Viewed State

    private var playedDotAnimationTarget: AnimationProgressTime?
    private var playedDotAnimationEnd: (() -> Void)?

    private func updateViewedState(animated: Bool = true) {
        let destination: AnimationProgressTime = isViewed ? 1 : 0

        // Do nothing if we're already there.
        guard destination != playedDotAnimation.currentProgress else { return }

        // Do nothing if we are already animating.
        if
            animated,
            playedDotAnimation.isAnimationQueued || playedDotAnimation.isAnimationPlaying,
            playedDotAnimationTarget == destination
        {
            return
        }

        playedDotAnimationTarget = destination
        playedDotAnimation.stop()

        if animated {
            playedDotAnimationEnd?()
            let endCellAnimation = audioMessageViewDelegate?.beginCellAnimation(maximumDuration: 0.2)
            playedDotAnimationEnd = endCellAnimation
            playedDotAnimation.play(toProgress: destination) { _ in
                endCellAnimation?()
            }
        } else {
            playedDotAnimationEnd?()
            playedDotAnimation.currentProgress = destination
        }
    }

    // MARK: Playback Rate

    private func updatePlaybackRate(animated: Bool) {
        let isPlaying: Bool = {
            guard attachmentStream != nil else {
                return false
            }
            let cvAudioPlayer = AppEnvironment.shared.cvAudioPlayerRef
            return cvAudioPlayer.audioPlaybackState(playbackID: playbackID) == .playing
        }()
        presentation.playbackRateView.setVisibility(isPlaying, animated: animated)
    }

    // MARK: - CVAudioPlayerListener

    func audioPlayerStateDidChange(playbackID: CVAudioPlaybackID) {
        AssertIsOnMainThread()

        guard playbackID == self.playbackID else { return }

        updateContents(animated: true)
    }

    func audioPlayerDidFinish(playbackID: CVAudioPlaybackID) {
        AssertIsOnMainThread()

        guard playbackID == self.playbackID else { return }

        updateContents(animated: true)
    }

    func audioPlayerDidMarkViewed(playbackID: CVAudioPlaybackID) {
        AssertIsOnMainThread()

        guard playbackID == self.playbackID else { return }

        setViewed(true, animated: true)
    }

    // MARK: - Thumb

    private static var thumbImageCache = [UIColor: UIImage]()

    private static func thumbImage(color: UIColor) -> UIImage {
        AssertIsOnMainThread()

        if let cachedImage = thumbImageCache[color] {
            return cachedImage
        }

        let image = UIGraphicsImageRenderer(size: Constants.thumbSize).image { _ in
            color.setFill()
            UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: Constants.thumbSize),
                cornerRadius: Constants.thumbSize.height / 2,
            ).fill()
        }
        thumbImageCache[color] = image
        return image
    }

    // MARK: - ProgressSlider

    // Overridden to set a custom track height.
    private class ProgressSlider: UISlider {
        override func trackRect(forBounds bounds: CGRect) -> CGRect {
            var rect = super.trackRect(forBounds: bounds)
            rect.size.height = Constants.progressTrackHeight
            rect.origin.y = (bounds.height - Constants.progressTrackHeight) / 2
            return rect
        }
    }
}
