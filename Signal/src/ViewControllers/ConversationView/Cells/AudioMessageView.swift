//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import UIKit

class AudioMessageView: ManualStackView {

    // MARK: - State

    private let threadUniqueId: String
    private let audioAttachment: AudioAttachment
    private var attachment: TSAttachment { audioAttachment.attachment }
    private var attachmentStream: TSAttachmentStream? { audioAttachment.attachmentStream }
    private var durationSeconds: TimeInterval { audioAttachment.durationSeconds }

    // Initially set to the value from the database (via itemViewState).
    // When the user changes the rate, model updates are paused via
    // `cvc_beginCellAnimation` and this value is updated. Once animations
    // are done, the whole cell gets recreated with the new plaback rate
    // value.
    private var audioPlaybackRate: AudioPlaybackRate

    private let isIncoming: Bool
    private weak var componentDelegate: CVComponentDelegate?
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
    private let playedDotContainer = ManualLayoutView(name: "playedDotContainer")
    private let playPauseAnimation: Lottie.AnimationView
    private let playPauseContainer = ManualLayoutView.circleView(name: "playPauseContainer")
    private let playbackTimeLabel = CVLabel()
    private let playbackRateView: AudioMessagePlaybackRateView
    private let progressSlider = UISlider()
    private let waveformProgress: AudioWaveformProgressView
    private let waveformContainer = ManualLayoutView(name: "waveformContainer")

    // MARK: Init

    init(
        threadUniqueId: String,
        audioAttachment: AudioAttachment,
        audioPlaybackRate: Float,
        isIncoming: Bool,
        componentDelegate: CVComponentDelegate,
        mediaCache: CVMediaCache
    ) {
        self.threadUniqueId = threadUniqueId
        self.audioAttachment = audioAttachment
        self.isIncoming = isIncoming
        self.componentDelegate = componentDelegate
        self.mediaCache = mediaCache
        self.audioPlaybackRate = AudioPlaybackRate(rawValue: audioPlaybackRate)

        self.waveformProgress = AudioWaveformProgressView(mediaCache: mediaCache)
        self.playedDotAnimation = mediaCache.buildLottieAnimationView(name: "audio-played-dot")
        self.playPauseAnimation = mediaCache.buildLottieAnimationView(name: "playPauseButton")

        self.playbackRateView = AudioMessagePlaybackRateView(
            threadUniqueId: threadUniqueId,
            audioAttachment: audioAttachment,
            playbackRate: AudioPlaybackRate(rawValue: audioPlaybackRate),
            isIncoming: isIncoming
        )

        super.init(name: "AudioMessageView")
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String, arrangedSubviews: [UIView] = []) {
        owsFail("Do not use this initializer.")
    }

    // MARK: - Rendering

    public func configureForRendering(
        cellMeasurement: CVCellMeasurement,
        conversationStyle: ConversationStyle
    ) {

        var outerSubviews = [UIView]()

        if let topLabelConfig = Self.topLabelConfig(audioAttachment: audioAttachment,
                                                    isIncoming: isIncoming,
                                                    conversationStyle: conversationStyle) {
            let topLabel = CVLabel()
            topLabelConfig.applyForRendering(label: topLabel)
            outerSubviews.append(topLabel)
        }

        waveformProgress.playedColor = playedColor
        waveformProgress.unplayedColor = unplayedColor
        waveformProgress.thumbColor = thumbColor
        waveformContainer.addSubviewToFillSuperviewEdges(waveformProgress)

        progressSlider.setThumbImage(UIImage(named: "audio_message_thumb")?.asTintedImage(color: thumbColor), for: .normal)
        progressSlider.setMinimumTrackImage(trackImage(color: playedColor), for: .normal)
        progressSlider.setMaximumTrackImage(trackImage(color: unplayedColor), for: .normal)
        progressSlider.isEnabled = audioAttachment.isDownloaded
        progressSlider.isUserInteractionEnabled = false

        waveformContainer.addSubview(progressSlider) { [progressSlider] view in
            var sliderFrame = view.bounds
            sliderFrame.height = 12
            sliderFrame.y = (view.bounds.height - sliderFrame.height) * 0.5
            progressSlider.frame = sliderFrame
        }

        let playbackTimeLabelConfig = Self.playbackTimeLabelConfig_render(isIncoming: isIncoming,
                                                                          conversationStyle: conversationStyle)
        playbackTimeLabelConfig.applyForRendering(label: playbackTimeLabel)
        playbackTimeLabel.setContentHuggingHigh()

        let leftView: UIView
        if audioAttachment.isDownloaded {
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
                ColorValueProvider(thumbColor.lottieColorValue),
                keypath: fillColorKeypath
            )
            playedDotAnimation.setValueProvider(
                ColorValueProvider(conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming).lottieColorValue),
                keypath: fillColorKeypath
            )

            playPauseContainer.backgroundColor = isIncoming
                ? (Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_whiteAlpha80)
                : .ows_whiteAlpha20
            playPauseContainer.addSubviewToCenterOnSuperview(playPauseAnimation, size: CGSize(square: 24))

            playedDotContainer.addSubviewToCenterOnSuperview(playedDotAnimation, size: CGSize(square: 16))

            leftView = playPauseContainer
        } else if let attachmentPointer = audioAttachment.attachmentPointer {
            leftView = CVAttachmentProgressView(direction: .download(attachmentPointer: attachmentPointer),
                                                diameter: Constants.animationSize,
                                                isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
                                                mediaCache: mediaCache)
        } else {
            owsFailDebug("Unexpected state.")
            leftView = UIView.transparentContainer()
        }

        let topInnerStack = ManualStackView(name: "playerStack")
        topInnerStack.semanticContentAttribute = .playback
        topInnerStack.configure(config: Self.topInnerStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_topInnerStack,
                             subviews: [
                                leftView,
                                .transparentSpacer(),
                                waveformContainer,
                                .transparentSpacer()
                             ])
        outerSubviews.append(topInnerStack)

        let bottomSubviews = [
                .transparentSpacer(),
                playbackTimeLabel,
                playedDotContainer,
                playbackRateView,
                .transparentSpacer()
        ]

        let bottomInnerStack = ManualStackView(name: "playbackLabelStack")
        bottomInnerStack.configure(
            config: Self.bottomInnerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_bottomInnerStack,
            subviews: bottomSubviews
        )
        outerSubviews.append(bottomInnerStack)

        self.configure(config: Self.outerStackConfig,
                       cellMeasurement: cellMeasurement,
                       measurementKey: Self.measurementKey_outerStack,
                       subviews: outerSubviews)

        updateContents(animated: false)

        cvAudioPlayer.addListener(self)
    }

    // MARK: - Measurement

    private static let measurementKey_topInnerStack = "CVComponentAudioAttachment.measurementKey_topInnerStack"
    private static let measurementKey_bottomInnerStack = "CVComponentAudioAttachment.measurementKey_bottomInnerStack"
    private static let measurementKey_outerStack = "CVComponentAudioAttachment.measurementKey_outerStack"

    public static func measure(
        maxWidth: CGFloat,
        audioAttachment: AudioAttachment,
        isIncoming: Bool,
        conversationStyle: ConversationStyle,
        measurementBuilder: CVCellMeasurement.Builder
    ) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var outerSubviewInfos = [ManualStackSubviewInfo]()
        if let topLabelConfig = Self.topLabelConfig(audioAttachment: audioAttachment,
                                                    isIncoming: isIncoming,
                                                    conversationStyle: conversationStyle) {
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

        let topInnerStackMeasurement = ManualStackView.measure(config: topInnerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_topInnerStack,
                                                            subviewInfos: topInnerSubviewInfos)
        let topInnerStackSize = topInnerStackMeasurement.measuredSize
        outerSubviewInfos.append(topInnerStackSize.ceil.asManualSubviewInfo)

        let dotSize = CGSize(square: 6)

        let playbackTimeLabelConfig = playbackTimeLabelConfig_forMeasurement(
            audioAttachment: audioAttachment,
            isIncoming: isIncoming,
            conversationStyle: conversationStyle,
            maxWidth: maxWidth
        )
        let playbackTimeLabelSize = CVText.measureLabel(config: playbackTimeLabelConfig, maxWidth: maxWidth)

        let playbackRateSize = AudioMessagePlaybackRateView.measure(maxWidth: maxWidth)

        var bottomInnerSubviewInfos: [ManualStackSubviewInfo] = [
            playbackTimeLabelSize.asManualSubviewInfo(hasFixedSize: true),
            dotSize.asManualSubviewInfo(hasFixedSize: true),
            playbackRateSize.asManualSubviewInfo(hasFixedSize: true)
        ]

        bottomInnerSubviewInfos.insert(CGSize.zero.asManualSubviewInfo(hasFixedWidth: true), at: 0)
        bottomInnerSubviewInfos.append(.empty)

        let bottomInnerStackMeasurement = ManualStackView.measure(config: bottomInnerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_bottomInnerStack,
                                                            subviewInfos: bottomInnerSubviewInfos)
        let bottomInnerStackSize = bottomInnerStackMeasurement.measuredSize
        outerSubviewInfos.append(bottomInnerStackSize.ceil.asManualSubviewInfo)

        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_outerStack,
                                                            subviewInfos: outerSubviewInfos,
                                                            maxWidth: maxWidth)
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

    private static var bottomInnerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: Constants.bottomInnerStackSpacing,
                          layoutMargins: .zero)
    }

    private static func topLabelConfig(audioAttachment: AudioAttachment,
                                       isIncoming: Bool,
                                       conversationStyle: ConversationStyle) -> CVLabelConfig? {

        let attachment = audioAttachment.attachment
        guard !attachment.isVoiceMessage else {
            return nil
        }

        let text: String
        if let fileName = attachment.sourceFilename?.stripped, !fileName.isEmpty {
            text = fileName
        } else {
            text = NSLocalizedString("GENERIC_ATTACHMENT_LABEL", comment: "A label for generic attachments.")
        }

        return CVLabelConfig(text: text,
                             font: Constants.labelFont,
                             textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming))
    }

    private static func playbackTimeLabelConfig_render(isIncoming: Bool,
                                                       conversationStyle: ConversationStyle) -> CVLabelConfig {
        playbackTimeLabelConfig(text: " ",
                                isIncoming: isIncoming,
                                conversationStyle: conversationStyle)
    }

    private static func playbackTimeLabelConfig_forMeasurement(
        audioAttachment: AudioAttachment,
        isIncoming: Bool,
        conversationStyle: ConversationStyle,
        maxWidth: CGFloat
    ) -> CVLabelConfig {
        // playbackTimeLabel uses a monospace font, so we measure the
        // worst-case width using the full duration of the audio.
        let text = OWSFormat.localizedDurationString(from: audioAttachment.durationSeconds)
        let fullDurationConfig = playbackTimeLabelConfig(
            text: text,
            isIncoming: isIncoming,
            conversationStyle: conversationStyle
        )
        // Never let it get shorter than "0:00" duration.
        let minimumWidthText = OWSFormat.localizedDurationString(from: 0)
        let minimumWidthConfig = playbackTimeLabelConfig(
            text: minimumWidthText,
            isIncoming: isIncoming,
            conversationStyle: conversationStyle
        )
        if minimumWidthConfig.measure(maxWidth: maxWidth).width > fullDurationConfig.measure(maxWidth: maxWidth).width {
            return minimumWidthConfig
        } else {
            return fullDurationConfig
        }
    }

    private static func playbackTimeLabelConfig(text: String,
                                                isIncoming: Bool,
                                                conversationStyle: ConversationStyle) -> CVLabelConfig {
        return CVLabelConfig(
            text: text,
            font: UIFont.ows_dynamicTypeCaption1Clamped,
            textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
        )
    }

    // MARK: - Constants

    fileprivate enum Constants {
        static let labelFont: UIFont = .ows_dynamicTypeCaption2
        static let waveformHeight: CGFloat = 32
        static let animationSize: CGFloat = 40
        static let vSpacing: CGFloat = 2
        static let innerLayoutMargins = UIEdgeInsets(hMargin: 0, vMargin: 4)

        static var bottomInnerStackSpacing: CGFloat {
            switch UIApplication.shared.preferredContentSizeCategory {
            case .extraSmall, .small, .medium, .large, .extraLarge:
                return 8
            default:
                return 4
            }
        }
    }

    // MARK: - Tapping

    public func handleTap(
        sender: UITapGestureRecognizer,
        itemModel: CVItemModel
    ) -> Bool {
        return playbackRateView.handleTap(sender: sender, itemModel: itemModel, componentDelegate: componentDelegate)
    }

    // MARK: - Scrubbing

    @objc
    var isScrubbing = false

    func isPointInScrubbableRegion(_ point: CGPoint) -> Bool {
        // If we have a waveform but aren't done sampling it, don't allow scrubbing yet.
        if let waveform = attachmentStream?.audioWaveform(), !waveform.isSamplingComplete {
            return false
        }

        let locationInSlider = convert(point, to: waveformProgress)
        return waveformProgress.bounds.contains(locationInSlider)
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

    private lazy var playedColor: UIColor = isIncoming
        ? (Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray60)
        : .ows_white
    private lazy var unplayedColor: UIColor = isIncoming
        ? (Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray25)
        : .ows_whiteAlpha40
    private lazy var thumbColor = playedColor

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
            let endCellAnimation = componentDelegate?.beginCellAnimation(maximumDuration: 0.2)
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
        playbackTimeLabel.text = OWSFormat.localizedDurationString(from: timeRemaining)
    }

    private func updateAudioProgress() {
        guard !isScrubbing else { return }

        visibleProgressRatio = audioProgressRatio

        if let waveform = attachmentStream?.audioWaveform() {
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
            let endCellAnimation = componentDelegate?.beginCellAnimation(maximumDuration: 0.2)
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
        playbackRateView.setVisibility(isPlaying, animated: animated)
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
