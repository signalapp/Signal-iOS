//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

class AudioMessageView: OWSStackView {

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
    private let conversationStyle: ConversationStyle

    private let playPauseAnimation = AnimationView(name: "playPauseButton")
    private let playbackTimeLabel = UILabel()
    private let progressSlider = UISlider()
    private let waveformProgress = AudioWaveformProgressView()

    private var audioPlaybackState: AudioPlaybackState {
        audioPlayer.audioPlaybackState(forAttachmentId: attachment.uniqueId)
    }

    private var elapsedSeconds: TimeInterval {
        guard let attachmentStream = self.attachmentStream else {
            return 0
        }
        return audioPlayer.playbackProgress(forAttachmentStream: attachmentStream)
    }

    @objc
    init(audioAttachment: AudioAttachment, isIncoming: Bool, conversationStyle: ConversationStyle) {
        self.audioAttachment = audioAttachment
        self.isIncoming = isIncoming
        self.conversationStyle = conversationStyle

        super.init(name: "AudioMessageView")

        self.apply(config: Self.outerStackConfig)

        if let topLabelConfig = Self.topLabelConfig(audioAttachment: audioAttachment,
                                           isIncoming: isIncoming,
                                           conversationStyle: conversationStyle) {
            let topLabel = UILabel()
            topLabelConfig.applyForRendering(label: topLabel)
            addArrangedSubview(topLabel)
        }

        // TODO: There is a bug with Lottie where animations lag when there are a lot
        // of other things happening on screen. Since this animation generally plays
        // when the progress bar / waveform is rendering we speed up the playback to
        // address some of the lag issues. Once this is fixed we should update lottie
        // and remove this check. https://github.com/airbnb/lottie-ios/issues/1034
        playPauseAnimation.animationSpeed = 3
        playPauseAnimation.backgroundBehavior = .forceFinish
        playPauseAnimation.contentMode = .scaleAspectFit
        playPauseAnimation.autoSetDimensions(to: CGSize(square: Self.animationSize))
        playPauseAnimation.setContentHuggingHigh()

        let fillColorKeypath = AnimationKeypath(keypath: "**.Fill 1.Color")
        playPauseAnimation.setValueProvider(ColorValueProvider(thumbColor.lottieColorValue), keypath: fillColorKeypath)

        let waveformContainer = UIView.container()
        waveformContainer.autoSetDimension(.height, toSize: AudioMessageView.waveformHeight)

        waveformProgress.playedColor = playedColor
        waveformProgress.unplayedColor = unplayedColor
        waveformProgress.thumbColor = thumbColor
        waveformContainer.addSubview(waveformProgress)
        waveformProgress.autoPinEdgesToSuperviewEdges()

        progressSlider.setThumbImage(UIImage(named: "audio_message_thumb")?.asTintedImage(color: thumbColor), for: .normal)
        progressSlider.setMinimumTrackImage(trackImage(color: playedColor), for: .normal)
        progressSlider.setMaximumTrackImage(trackImage(color: unplayedColor), for: .normal)

        waveformContainer.addSubview(progressSlider)
        progressSlider.autoPinWidthToSuperview()
        progressSlider.autoSetDimension(.height, toSize: 12)
        progressSlider.autoVCenterInSuperview()
        progressSlider.isEnabled = isDownloaded

        Self.playbackTimeLabelConfig(isIncoming: isIncoming,
                                     conversationStyle: conversationStyle).applyForRendering(label: playbackTimeLabel)
        playbackTimeLabel.setContentHuggingHigh()

        let leftView: UIView
        if isDownloaded {
            leftView = playPauseAnimation
        } else {
            let iconView = UIImageView.withTemplateImageName("arrow-down-24",
                                                             tintColor: Theme.accentBlueColor)
            iconView.autoSetDimensions(to: CGSize.square(20))
            let progressView = CircularProgressView(thickness: 0.1)
            progressView.progress = 0.0
            progressView.autoSetDimensions(to: CGSize(square: Self.animationSize))
            progressView.addSubview(iconView)
            iconView.autoCenterInSuperview()
            leftView = progressView
        }

        let innerStack = OWSStackView(name: "playerStack",
                                      arrangedSubviews: [leftView, waveformContainer, playbackTimeLabel])
        innerStack.apply(config: Self.innerStackConfig)
        addArrangedSubview(innerStack)

        updateContents(animated: false)

        audioPlayer.addListener(self)
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

    private static func playbackTimeLabelConfig(isIncoming: Bool,
                                                conversationStyle: ConversationStyle) -> CVLabelConfig {
        return CVLabelConfig(text: " ",
                             font: UIFont.ows_dynamicTypeCaption1.ows_monospaced,
                             textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming))
    }

    @objc
    static func measureHeight(audioAttachment: AudioAttachment,
                              isIncoming: Bool,
                              conversationStyle: ConversationStyle) -> CGFloat {

        var outerSubviewSizes = [CGSize]()
        if let topLabelConfig = Self.topLabelConfig(audioAttachment: audioAttachment,
                                                    isIncoming: isIncoming,
                                                    conversationStyle: conversationStyle) {
            outerSubviewSizes.append(CGSize(width: 0, height: topLabelConfig.font.lineHeight))
        }

        let playPauseAnimationSize = CGSize(square: animationSize)
        let waveformSize = CGSize(width: 0, height: waveformHeight)
        let playbackTimeLabelSize = CGSize(width: 0, height: playbackTimeLabelConfig(isIncoming: isIncoming,
                                                                                     conversationStyle: conversationStyle).font.lineHeight)
        let innerSubviewSizes = [playPauseAnimationSize, waveformSize, playbackTimeLabelSize]
        let innerStackSize = CVStackView.measure(config: innerStackConfig, subviewSizes: innerSubviewSizes)
        outerSubviewSizes.append(innerStackSize)

        let outerStackSize = CVStackView.measure(config: outerStackConfig, subviewSizes: outerSubviewSizes)
        return outerStackSize.height
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
//        showDownloadProgressIfNecessary()
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

//    private func showDownloadProgressIfNecessary() {
//        guard let attachmentPointer = attachment as? TSAttachmentPointer else { return }
//
//        // We don't need to handle the "tap to retry" state here,
//        // only download progress.
//        guard .failed != attachmentPointer.state else { return }
//
//        // TODO: Show "restoring" indicator and possibly progress.
//        guard .restoring != attachmentPointer.pointerType else { return }
//
//        guard attachmentPointer.uniqueId.count > 1 else {
//            return owsFailDebug("missing unique id")
//        }
//
//        // Add the download view to the play pause animation. This view
//        // will get recreated once the download completes so we don't
//        // have to worry about resetting anything.
//        let downloadView = MediaDownloadView(attachmentId: attachmentPointer.uniqueId, radius: iconSize * 0.5)
//        playPauseAnimation.animation = nil
//        playPauseAnimation.addSubview(downloadView)
//        downloadView.autoSetDimensions(to: CGSize(square: iconSize))
//        downloadView.autoCenterInSuperview()
//    }

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
