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

    private let playPauseAnimation = AnimationView(name: "playPauseButton")
    private let playbackTimeLabel = CVLabel()
    private let progressSlider = UISlider()
    private let waveformProgress = AudioWaveformProgressView()
    private let waveformContainer = OWSLayerView()

    private var audioPlaybackState: AudioPlaybackState {
        cvAudioPlayer.audioPlaybackState(forAttachmentId: attachment.uniqueId)
    }

    private var elapsedSeconds: TimeInterval {
        guard let attachmentStream = self.attachmentStream else {
            return 0
        }
        return cvAudioPlayer.playbackProgress(forAttachmentStream: attachmentStream)
    }

    @objc
    init(audioAttachment: AudioAttachment, isIncoming: Bool) {
        self.audioAttachment = audioAttachment
        self.isIncoming = isIncoming

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
        waveformContainer.addSubview(waveformProgress)

        progressSlider.setThumbImage(UIImage(named: "audio_message_thumb")?.asTintedImage(color: thumbColor), for: .normal)
        progressSlider.setMinimumTrackImage(trackImage(color: playedColor), for: .normal)
        progressSlider.setMaximumTrackImage(trackImage(color: unplayedColor), for: .normal)
        waveformContainer.addSubview(progressSlider)
        progressSlider.isEnabled = isDownloaded

        let waveformProgress = self.waveformProgress
        let progressSlider = self.progressSlider
        waveformContainer.layoutCallback = { view in
            waveformProgress.frame = view.bounds

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
            // TODO: There is a bug with Lottie where animations lag when there are a lot
            // of other things happening on screen. Since this animation generally plays
            // when the progress bar / waveform is rendering we speed up the playback to
            // address some of the lag issues. Once this is fixed we should update lottie
            // and remove this check. https://github.com/airbnb/lottie-ios/issues/1034
            playPauseAnimation.animationSpeed = 3
            playPauseAnimation.backgroundBehavior = .forceFinish
            playPauseAnimation.contentMode = .scaleAspectFit

            let fillColorKeypath = AnimationKeypath(keypath: "**.Fill 1.Color")
            playPauseAnimation.setValueProvider(ColorValueProvider(thumbColor.lottieColorValue), keypath: fillColorKeypath)

            leftView = playPauseAnimation
        } else if let attachmentPointer = audioAttachment.attachmentPointer {
            leftView = CVAttachmentProgressView(direction: .download(attachmentPointer: attachmentPointer),
                                                style: .withoutCircle(diameter: Self.animationSize),
                                                conversationStyle: conversationStyle)
        } else {
            owsFailDebug("Unexpected state.")
            leftView = UIView.transparentContainer()
        }

        let innerStack = ManualStackView(name: "playerStack")
        innerStack.configure(config: Self.innerStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_innerStack,
                             subviews: [
                                leftView,
                                waveformContainer,
                                playbackTimeLabel
                             ])
        outerSubviews.append(innerStack)

        self.configure(config: Self.outerStackConfig,
                       cellMeasurement: cellMeasurement,
                       measurementKey: Self.measurementKey_outerStack,
                       subviews: outerSubviews)

        updateContents(animated: false)

        cvAudioPlayer.addListener(self)
    }

    private static let measurementKey_innerStack = "CVComponentAudioAttachment.measurementKey_innerStack"
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

        var innerSubviewInfos = [ManualStackSubviewInfo]()
        let leftViewSize = CGSize(square: animationSize)
        innerSubviewInfos.append(leftViewSize.asManualSubviewInfo(hasFixedSize: true))

        let waveformSize = CGSize(width: 0, height: waveformHeight)
        innerSubviewInfos.append(waveformSize.asManualSubviewInfo)

        let playbackTimeLabelConfig = playbackTimeLabelConfig_forMeasurement(audioAttachment: audioAttachment,
                                                                             isIncoming: isIncoming,
                                                                             conversationStyle: conversationStyle)
        let playbackTimeLabelSize = CVText.measureLabel(config: playbackTimeLabelConfig, maxWidth: maxWidth)
        innerSubviewInfos.append(playbackTimeLabelSize.asManualSubviewInfo(hasFixedWidth: true))

        let innerStackMeasurement = ManualStackView.measure(config: innerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_innerStack,
                                                            subviewInfos: innerSubviewInfos)
        let innerStackSize = innerStackMeasurement.measuredSize
        outerSubviewInfos.append(innerStackSize.ceil.asManualSubviewInfo)

        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_outerStack,
                                                            subviewInfos: outerSubviewInfos)
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

    private static var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 12,
                          layoutMargins: innerLayoutMargins)
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
    private static var waveformHeight: CGFloat = 35
    private static var animationSize: CGFloat = 28
    private var iconSize: CGFloat = 24
    private static var vSpacing: CGFloat = 2
    private static var innerLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(hMargin: 0, vMargin: 4)
    }

    private lazy var playedColor: UIColor = isIncoming ? .init(rgbHex: 0x92caff) : .ows_white
    private lazy var unplayedColor: UIColor =
        isIncoming ? Theme.secondaryTextAndIconColor.withAlphaComponent(0.3) : UIColor.ows_white.withAlphaComponent(0.6)
    private lazy var thumbColor: UIColor = isIncoming ? Theme.secondaryTextAndIconColor : .ows_white

    // If set, the playback should reflect
    // this progress, not the actual progress.
    // During pan gestures, this gives a preview
    // of playback scrubbing.
    private var overrideProgress: CGFloat?

    func updateContents(animated: Bool) {
        updatePlaybackState(animated: animated)
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

        if animated {
            playPauseAnimation.play(toProgress: destination)
        } else {
            playPauseAnimation.currentProgress = destination
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
    func audioPlayerStateDidChange() {
        AssertIsOnMainThread()

        updateContents(animated: true)
    }
}
