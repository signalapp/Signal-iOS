//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

class AudioMessageView: ManualStackView {

    private let audioAttachment: AudioAttachment
    private var attachment: TSAttachment { audioAttachment.attachment }
    private var attachmentStream: TSAttachmentStream? { audioAttachment.attachmentStream }
    private var durationSeconds: TimeInterval { audioAttachment.durationSeconds }
    private var isDownloaded: Bool { audioAttachment.attachmentStream != nil }
    private var isDownloading: Bool {
        guard let attachmentPointer = audioAttachment.attachmentPointer else {
            return false
        }
        switch attachmentPointer.state {
        case .failed, .pendingMessageRequest, .pendingManualDownload:
            return false
        case .enqueued, .downloading:
            return true
        @unknown default:
            owsFailDebug("Invalid value.")
            return false
        }
    }

    private let isIncoming: Bool
    private weak var componentDelegate: CVComponentDelegate?

    private let playedDotAnimation = AnimationView(name: "audio-played-dot")
    private let playedDotContainer = ManualLayoutView(name: "playedDotContainer")
    private let playPauseAnimation = AnimationView(name: "playPauseButton")
    private let playPauseContainer = ManualLayoutView.circleView(name: "playPauseContainer")
    private let playbackTimeLabel = CVLabel()
    private let progressSlider = UISlider()
    private let waveformProgress = AudioWaveformProgressView()
    private let waveformContainer = ManualLayoutView(name: "waveformContainer")

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

    @objc
    init(audioAttachment: AudioAttachment, isIncoming: Bool, componentDelegate: CVComponentDelegate) {
        self.audioAttachment = audioAttachment
        self.isIncoming = isIncoming
        self.componentDelegate = componentDelegate

        super.init(name: "AudioMessageView")
    }

    public func configureForRendering(cellMeasurement: CVCellMeasurement,
                                      conversationStyle: ConversationStyle) {

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
        progressSlider.isEnabled = isDownloaded
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
        if isDownloaded {
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
                                                style: .withoutCircle(diameter: Self.animationSize),
                                                conversationStyle: conversationStyle)
        } else {
            owsFailDebug("Unexpected state.")
            leftView = UIView.transparentContainer()
        }

        let topInnerStack = ManualStackView(name: "playerStack")
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

        let bottomSubviews: [UIView]
        if isIncoming {
            bottomSubviews = [
                .transparentSpacer(),
                playedDotContainer,
                playbackTimeLabel
            ]
        } else {
            bottomSubviews = [
                .transparentSpacer(),
                playbackTimeLabel,
                playedDotContainer,
                .transparentSpacer()
            ]
        }

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

    private static let measurementKey_topInnerStack = "CVComponentAudioAttachment.measurementKey_topInnerStack"
    private static let measurementKey_bottomInnerStack = "CVComponentAudioAttachment.measurementKey_bottomInnerStack"
    private static let measurementKey_outerStack = "CVComponentAudioAttachment.measurementKey_outerStack"

    public static func measure(maxWidth: CGFloat,
                               audioAttachment: AudioAttachment,
                               isIncoming: Bool,
                               conversationStyle: ConversationStyle,
                               measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var outerSubviewInfos = [ManualStackSubviewInfo]()
        if let topLabelConfig = Self.topLabelConfig(audioAttachment: audioAttachment,
                                                    isIncoming: isIncoming,
                                                    conversationStyle: conversationStyle) {
            let topLabelSize = CGSize(width: 0, height: topLabelConfig.font.lineHeight)
            outerSubviewInfos.append(topLabelSize.asManualSubviewInfo)
        }

        var topInnerSubviewInfos = [ManualStackSubviewInfo]()
        let leftViewSize = CGSize(square: animationSize)
        topInnerSubviewInfos.append(leftViewSize.asManualSubviewInfo(hasFixedSize: true))

        topInnerSubviewInfos.append(CGSize(width: 12, height: 0).asManualSubviewInfo(hasFixedWidth: true))

        let waveformSize = CGSize(width: 0, height: waveformHeight)
        topInnerSubviewInfos.append(waveformSize.asManualSubviewInfo(hasFixedHeight: true))

        topInnerSubviewInfos.append(CGSize(width: 6, height: 0).asManualSubviewInfo(hasFixedWidth: true))

        let topInnerStackMeasurement = ManualStackView.measure(config: topInnerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_topInnerStack,
                                                            subviewInfos: topInnerSubviewInfos)
        let topInnerStackSize = topInnerStackMeasurement.measuredSize
        outerSubviewInfos.append(topInnerStackSize.ceil.asManualSubviewInfo)

        let dotSize = CGSize(square: 6)

        let playbackTimeLabelConfig = playbackTimeLabelConfig_forMeasurement(audioAttachment: audioAttachment,
                                                                             isIncoming: isIncoming,
                                                                             conversationStyle: conversationStyle)
        let playbackTimeLabelSize = CVText.measureLabel(config: playbackTimeLabelConfig, maxWidth: maxWidth)

        let bottomInnerSubviewInfos: [ManualStackSubviewInfo]
        if isIncoming {
            bottomInnerSubviewInfos = [
                .empty,
                dotSize.asManualSubviewInfo(hasFixedSize: true),
                playbackTimeLabelSize.asManualSubviewInfo(hasFixedSize: true)
            ]
        } else {
            let leadingInset = CGSize(width: 44, height: 0)
            bottomInnerSubviewInfos = [
                leadingInset.asManualSubviewInfo(hasFixedWidth: true),
                playbackTimeLabelSize.asManualSubviewInfo(hasFixedSize: true),
                dotSize.asManualSubviewInfo(hasFixedSize: true),
                .empty
            ]
        }

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

    @available(swift, obsoleted: 1.0)
    required init(name: String, arrangedSubviews: [UIView] = []) {
        owsFail("Do not use this initializer.")
    }

    private static var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: vSpacing,
                          layoutMargins: .zero)
    }

    private static var topInnerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: innerLayoutMargins)
    }

    private static var bottomInnerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 8,
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
                             font: labelFont,
                             textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming))
    }

    private static func playbackTimeLabelConfig_render(isIncoming: Bool,
                                                       conversationStyle: ConversationStyle) -> CVLabelConfig {
        playbackTimeLabelConfig(text: " ",
                                isIncoming: isIncoming,
                                conversationStyle: conversationStyle)
    }

    private static func playbackTimeLabelConfig_forMeasurement(audioAttachment: AudioAttachment,
                                                               isIncoming: Bool,
                                                               conversationStyle: ConversationStyle) -> CVLabelConfig {
        // playbackTimeLabel uses a monospace font, so we measure the
        // worst-case width using the full duration of the audio.
        let text = OWSFormat.formatDurationSeconds(Int(audioAttachment.durationSeconds))
        return playbackTimeLabelConfig(text: text,
                                       isIncoming: isIncoming,
                                       conversationStyle: conversationStyle)
    }

    private static func playbackTimeLabelConfig(text: String,
                                                isIncoming: Bool,
                                                conversationStyle: ConversationStyle) -> CVLabelConfig {
        CVLabelConfig(text: text,
                      font: UIFont.ows_dynamicTypeCaption1.ows_monospaced,
                      textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming))
    }

    // MARK: - Scrubbing

    @objc var isScrubbing = false

    @objc
    func isPointInScrubbableRegion(_ point: CGPoint) -> Bool {
        // If we have a waveform but aren't done sampling it, don't allow scrubbing yet.
        if let waveform = attachmentStream?.audioWaveform(), !waveform.isSamplingComplete {
            return false
        }

        let locationInSlider = convert(point, to: waveformProgress)
        return locationInSlider.x >= 0 && locationInSlider.x <= waveformProgress.width
    }

    @objc
    func progressForLocation(_ point: CGPoint) -> CGFloat {
        let sliderContainer = convert(waveformProgress.frame, from: waveformProgress.superview)
        var newRatio = CGFloatInverseLerp(point.x, sliderContainer.minX, sliderContainer.maxX).clamp01()

        // When in RTL mode, the slider moves in the opposite direction so inverse the ratio.
        if CurrentAppContext().isRTL {
            newRatio = 1 - newRatio
        }

        return newRatio.clamp01()
    }

    @objc
    func scrubToLocation(_ point: CGPoint) -> TimeInterval {
        let newRatio = progressForLocation(point)

        visibleProgressRatio = newRatio

        return TimeInterval(newRatio) * durationSeconds
    }

    // MARK: - Contents

    private static var labelFont: UIFont = .ows_dynamicTypeCaption2
    private static var waveformHeight: CGFloat = 32
    private static var animationSize: CGFloat = 40
    private static var vSpacing: CGFloat = 2
    private static var innerLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(hMargin: 0, vMargin: 4)
    }

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
    }

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

    private func updatePlaybackState(animated: Bool = true) {
        let isPlaying = audioPlaybackState == .playing
        let destination: AnimationProgressTime = isPlaying ? 1 : 0

        // Do nothing if we're already there.
        guard destination != playPauseAnimation.currentProgress else { return }

        if animated {
            let endCellAnimation = componentDelegate?.cvc_beginCellAnimation(maximumDuration: 0.2)
            playPauseAnimation.play(toProgress: destination) { _ in
                endCellAnimation?()
            }
        } else {
            playPauseAnimation.currentProgress = destination
        }
    }

    private func updateViewedState(animated: Bool = true) {
        var isViewed = self.isViewed

        // If we don't support viewed receipts yet, never show
        // the unviewed dot.
        if !RemoteConfig.viewedReceiptSending { isViewed = true }

        let destination: AnimationProgressTime = isViewed ? 1 : 0

        // Do nothing if we're already there.
        guard destination != playedDotAnimation.currentProgress else { return }

        if animated {
            let endCellAnimation = componentDelegate?.cvc_beginCellAnimation(maximumDuration: 0.2)
            playedDotAnimation.play(toProgress: destination) { _ in
                endCellAnimation?()
            }
        } else {
            playedDotAnimation.currentProgress = destination
        }
    }

    private func updateElapsedTime(_ elapsedSeconds: TimeInterval) {
        let timeRemaining = Int(durationSeconds - elapsedSeconds)
        playbackTimeLabel.text = OWSFormat.formatDurationSeconds(timeRemaining)
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
}

// MARK: -

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
