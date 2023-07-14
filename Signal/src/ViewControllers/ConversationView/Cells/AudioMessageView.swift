//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

class AudioMessageView: ManualStackView {
    private enum Constants {
        static let animationSize: CGFloat = 40
        static let waveformHeight: CGFloat = 32
        static let vSpacing: CGFloat = 2
        static let innerLayoutMargins = UIEdgeInsets(hMargin: 0, vMargin: 4)
    }
    // MARK: - State
    private var attachment: TSAttachment { presentation.audioAttachment.attachment }
    private var attachmentStream: TSAttachmentStream? { presentation.audioAttachment.attachmentStream }
    private var durationSeconds: TimeInterval { presentation.audioAttachment.durationSeconds }

    private var isIncoming: Bool {
        presentation.isIncoming
    }
    private weak var audioMessageViewDelegate: AudioMessageViewDelegate?
    private let mediaCache: CVMediaCache

    private var audioPlaybackState: AudioPlaybackState {
        cvAudioPlayer.audioPlaybackState(forAttachmentId: attachment.uniqueId)
    }

    private var elapsedSeconds: TimeInterval {
        guard let attachmentStream = self.attachmentStream else {
            return 0
        }
        return cvAudioPlayer.playbackProgress(forAttachmentStream: attachmentStream)
    }

    private var isViewed = false
    public func setViewed(_ isViewed: Bool, animated: Bool) {
        guard isViewed != self.isViewed else { return }
        self.isViewed = isViewed
        updateContents(animated: animated)
    }

    // MARK: - Views

    private let playedDotAnimation: Lottie.AnimationView
    private let playPauseAnimation: Lottie.AnimationView
    private let playPauseContainer = ManualLayoutView.circleView(name: "playPauseContainer")
    private let progressSlider = UISlider()
    private let waveformProgress: AudioWaveformProgressView
    private let waveformContainer = ManualLayoutView(name: "waveformContainer")
    private let presentation: AudioPresenter

    // MARK: Init

    init(
        presentation: AudioPresenter,
        audioMessageViewDelegate: AudioMessageViewDelegate,
        mediaCache: CVMediaCache
    ) {
        self.audioMessageViewDelegate = audioMessageViewDelegate
        self.mediaCache = mediaCache

        self.waveformProgress = AudioWaveformProgressView(mediaCache: mediaCache)
        self.playedDotAnimation = mediaCache.buildLottieAnimationView(name: "audio-played-dot")
        self.playPauseAnimation = mediaCache.buildLottieAnimationView(name: "playPauseButton")
        self.presentation = presentation

        super.init(name: presentation.name)
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String, arrangedSubviews: [UIView] = []) {
        owsFail("Do not use this initializer.")
    }

    // MARK: - Rendering

    public func configureForRendering(cellMeasurement: CVCellMeasurement, conversationStyle: ConversationStyle) {
        var outerSubviews = [UIView]()

        if let topLabelConfig = presentation.topLabelConfig(
            audioAttachment: presentation.audioAttachment,
            isIncoming: isIncoming,
            conversationStyle: conversationStyle
        ) {
            let topLabel = CVLabel()
            topLabelConfig.applyForRendering(label: topLabel)
            outerSubviews.append(topLabel)
        }

        waveformProgress.playedColor = presentation.playedColor(isIncoming: isIncoming)
        waveformProgress.unplayedColor = presentation.unplayedColor(isIncoming: isIncoming)
        waveformProgress.thumbColor = presentation.thumbColor(isIncoming: isIncoming)
        waveformContainer.addSubviewToFillSuperviewEdges(waveformProgress)

        progressSlider.setThumbImage(UIImage(named: "audio_message_thumb")?.asTintedImage(color: presentation.thumbColor(isIncoming: isIncoming)), for: .normal)
        progressSlider.setMinimumTrackImage(trackImage(color: presentation.playedColor(isIncoming: isIncoming)), for: .normal)
        progressSlider.setMaximumTrackImage(trackImage(color: presentation.unplayedColor(isIncoming: isIncoming)), for: .normal)
        progressSlider.isEnabled = presentation.audioAttachment.isDownloaded
        progressSlider.isUserInteractionEnabled = false

        waveformContainer.addSubview(progressSlider) { [progressSlider] view in
            var sliderFrame = view.bounds
            sliderFrame.height = 12
            sliderFrame.y = (view.bounds.height - sliderFrame.height) * 0.5
            progressSlider.frame = sliderFrame
        }

        presentation.configureForRendering(conversationStyle: conversationStyle)

        let leftView: UIView
        if presentation.audioAttachment.isDownloaded {
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
                presentation.playPauseAnimationColor(isIncoming: isIncoming),
                keypath: fillColorKeypath
            )
            playedDotAnimation.setValueProvider(
                presentation.playedDotAnimationColor(conversationStyle: conversationStyle, isIncoming: isIncoming),
                keypath: fillColorKeypath
            )

            playPauseContainer.backgroundColor = presentation.playPauseContainerBackgroundColor(isIncoming: isIncoming)
            playPauseContainer.addSubviewToCenterOnSuperview(playPauseAnimation, size: CGSize(square: 24))

            presentation.playedDotContainer.addSubviewToCenterOnSuperview(playedDotAnimation, size: CGSize(square: 16))

            leftView = playPauseContainer
        } else if let attachmentPointer = presentation.audioAttachment.attachmentPointer {
            leftView = CVAttachmentProgressView(
                direction: .download(attachmentPointer: attachmentPointer),
                diameter: Constants.animationSize,
                isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
                mediaCache: mediaCache
            )
        } else {
            owsFailDebug("Unexpected state.")
            leftView = UIView.transparentContainer()
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
                .transparentSpacer()
            ]
        )
        outerSubviews.append(topInnerStack)

        let generators = presentation.bottomSubviewGenerators(conversationStyle: conversationStyle)

        let bottomInnerStack = ManualStackView(name: "playbackLabelStack")
        bottomInnerStack.configure(
            config: Self.bottomInnerStackConfig(presentation: presentation),
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_bottomInnerStack,
            subviews: generators.map { $0.viewGenerator() }
        )
        outerSubviews.append(bottomInnerStack)

        self.configure(
            config: Self.outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: outerSubviews
        )

        updateContents(animated: false)

        cvAudioPlayer.addListener(self)
    }

    // MARK: - Measurement

    private static let measurementKey_topInnerStack = "CVComponentAudioAttachment.measurementKey_topInnerStack"
    private static let measurementKey_bottomInnerStack = "CVComponentAudioAttachment.measurementKey_bottomInnerStack"
    private static let measurementKey_outerStack = "CVComponentAudioAttachment.measurementKey_outerStack"

    public static func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        presentation: AudioPresenter
    ) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var outerSubviewInfos = [ManualStackSubviewInfo]()
        if let topLabelConfig = presentation.topLabelConfig(
            audioAttachment: presentation.audioAttachment,
            isIncoming: presentation.isIncoming,
            conversationStyle: nil
        ) {
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
            subviewInfos: topInnerSubviewInfos
        )
        let topInnerStackSize = topInnerStackMeasurement.measuredSize
        outerSubviewInfos.append(topInnerStackSize.ceil.asManualSubviewInfo)

        let bottomInnerStackMeasurement = ManualStackView.measure(
            config: bottomInnerStackConfig(presentation: presentation),
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_bottomInnerStack,
            subviewInfos: presentation.bottomSubviewGenerators(conversationStyle: nil).map { $0.measurementInfo(maxWidth) }
        )
        let bottomInnerStackSize = bottomInnerStackMeasurement.measuredSize
        outerSubviewInfos.append(bottomInnerStackSize.ceil.asManualSubviewInfo)

        let outerStackMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: outerSubviewInfos,
            maxWidth: maxWidth
        )
        return outerStackMeasurement.measuredSize
    }

    // MARK: - View Configs

    private static var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: Constants.vSpacing,
                          layoutMargins: .zero)
    }

    private static var topInnerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: Constants.innerLayoutMargins)
    }

    private static func bottomInnerStackConfig(presentation: AudioPresenter) -> CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: presentation.bottomInnerStackSpacing,
                          layoutMargins: .zero)
    }

    // MARK: - Tapping

    public func handleTap(sender: UITapGestureRecognizer, itemModel: CVItemModel) -> Bool {
        presentation.playbackRateView.handleTap(
            sender: sender,
            itemModel: itemModel,
            audioMessageViewDelegate: audioMessageViewDelegate
        )
    }

    // MARK: - Scrubbing

    var isScrubbing = false

    func isPointInScrubbableRegion(_ point: CGPoint) -> Bool {
        // If we have a waveform but aren't done sampling it, don't allow scrubbing yet.
        if let waveform = attachmentStream?.audioWaveform(), !waveform.isSamplingComplete {
            return false
        }

        let locationInSlider = convert(point, to: waveformProgress)
        return locationInSlider.x >= 0 && locationInSlider.x <= waveformProgress.width
    }

    func progressForLocation(_ point: CGPoint) -> CGFloat {
        let sliderContainer = convert(waveformProgress.frame, from: waveformProgress.superview)
        let newRatio = CGFloatInverseLerp(point.x, sliderContainer.minX, sliderContainer.maxX).clamp01()
        return newRatio.clamp01()
    }

    func scrubToLocation(_ point: CGPoint) -> TimeInterval {
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
        guard durationSeconds > 0 else { return 0 }
        return CGFloat(elapsedSeconds / durationSeconds)
    }

    private var visibleProgressRatio: CGFloat {
        get {
            waveformProgress.value
        }
        set {
            waveformProgress.value = newValue
            progressSlider.value = Float(newValue)
            updateElapsedTime(durationSeconds * TimeInterval(newValue))
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

    private func updateElapsedTime(_ elapsedSeconds: TimeInterval) {
        let timeRemaining = max(0, durationSeconds - elapsedSeconds)
        presentation.playbackTimeLabel.text = OWSFormat.localizedDurationString(from: timeRemaining)
    }

    private func updateAudioProgress() {
        guard !isScrubbing else { return }

        visibleProgressRatio = audioProgressRatio

        if let waveform = presentation.audioWaveform(attachmentStream: attachmentStream) {
            waveformProgress.audioWaveform = waveform
            waveformProgress.isHidden = false
            progressSlider.isHidden = true
        } else {
            waveformProgress.isHidden = true
            progressSlider.isHidden = false
        }
    }

    public func setOverrideProgress(_ value: CGFloat, animated: Bool) {
        overrideProgress = value
        updateContents(animated: animated)
    }

    public func clearOverrideProgress(animated: Bool) {
        overrideProgress = nil
        updateContents(animated: animated)
    }

    private func trackImage(color: UIColor) -> UIImage? {
        return UIImage(named: "audio_message_track")?
            .asTintedImage(color: color)?
            .resizableImage(withCapInsets: UIEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))
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
            guard let attachmentStream = attachmentStream else {
                return false
            }
            return cvAudioPlayer.audioPlaybackState(forAttachmentId: attachmentStream.uniqueId) == .playing
        }()
        presentation.playbackRateView.setVisibility(isPlaying, animated: animated)
    }
}

// MARK: - CVAudioPlayerListener

extension AudioMessageView: CVAudioPlayerListener {
    func audioPlayerStateDidChange(attachmentId: String) {
        AssertIsOnMainThread()

        guard attachmentId == attachment.uniqueId else { return }

        updateContents(animated: true)
    }

    func audioPlayerDidFinish(attachmentId: String) {
        AssertIsOnMainThread()

        guard attachmentId == attachment.uniqueId else { return }

        updateContents(animated: true)
    }

    func audioPlayerDidMarkViewed(attachmentId: String) {
        AssertIsOnMainThread()

        guard !isViewed, attachmentId == attachment.uniqueId else { return }

        setViewed(true, animated: true)
    }
}

extension AudioAttachment {
    var sizeString: String {
        switch state {
        case .attachmentStream(attachmentStream: let stream, audioDurationSeconds: _):
            return ByteCountFormatter().string(for: stream.byteCount) ?? ""
        case .attachmentPointer:
            owsFailDebug("Shouldn't get here - undownloaded media not implemented")
            return ""
        }
    }
    var dateString: String {
        switch state {
        case .attachmentStream(attachmentStream: let stream, audioDurationSeconds: _):
            let dateFormatter = DateFormatter()
            dateFormatter.setLocalizedDateFormatFromTemplate("Mdyy")
            return dateFormatter.string(from: stream.creationTimestamp)
        case .attachmentPointer:
            owsFailDebug("Shouldn't get here - undownloaded media not implemented")
            return ""
        }
    }
}
