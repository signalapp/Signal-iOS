//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// Defines the look of audio messages in the conversation view.
class AudioMessagePresenter: AudioPresenter {
    let name = "AudioMessageView"
    let playbackTimeLabel = CVLabel()
    let playedDotContainer = ManualLayoutView(name: "playedDotContainer")
    let playbackRateView: AudioMessagePlaybackRateView
    let audioAttachment: AudioAttachment
    let threadUniqueId: String
    let audioPlaybackRate: AudioPlaybackRate

    private let isIncoming: Bool

    init(
        isIncoming: Bool,
        audioAttachment: AudioAttachment,
        threadUniqueId: String,
        playbackRate: AudioPlaybackRate,
    ) {
        self.threadUniqueId = threadUniqueId
        self.audioPlaybackRate = playbackRate
        self.isIncoming = isIncoming
        self.audioAttachment = audioAttachment
        self.playbackRateView = AudioMessagePlaybackRateView(
            threadUniqueId: threadUniqueId,
            audioAttachment: audioAttachment,
            playbackRate: playbackRate,
            isIncoming: isIncoming,
        )
    }

    var bottomInnerStackSpacing: CGFloat {
        switch UIApplication.shared.preferredContentSizeCategory {
        case .extraSmall, .small, .medium, .large, .extraLarge:
            return 8
        default:
            return 4
        }
    }

    func playedColor() -> UIColor {
        isIncoming ? .Signal.secondaryLabel : .Signal.ColorBase.labelPrimary
    }

    func unplayedColor() -> UIColor {
        isIncoming ? .Signal.quaternaryLabel : .Signal.ColorBase.labelTertiary
    }

    // Over the waveform the thumb sits among the bars, so it takes the label
    // color to stand apart from them.
    func waveformThumbColor() -> UIColor {
        isIncoming ? .Signal.label : .Signal.ColorBase.labelPrimary
    }

    // On the bare progress bar it's a capsule handle, white in both incoming
    // and outgoing bubbles.
    func progressBarThumbColor() -> UIColor {
        .Signal.ColorBase.labelPrimary
    }

    func playPauseContainerBackgroundColor(conversationStyle: ConversationStyle) -> UIColor {
        switch (isIncoming, conversationStyle.hasWallpaper) {
        case (true, true): .Signal.MaterialBase.button
        case (true, _): .Signal.LightBase.button
        case (false, _): .Signal.ColorBase.button
        }
    }

    func playPauseAnimationColor() -> UIColor {
        isIncoming ? .Signal.label : .Signal.ColorBase.labelPrimary
    }

    func playedDotAnimationColor(conversationStyle: ConversationStyle) -> UIColor {
        conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
    }

    func progressViewConfiguration(conversationStyle: ConversationStyle) -> CVAttachmentProgressView.Configuration {
        CVAttachmentProgressView.Configuration(
            conversationStyle: conversationStyle,
            isIncoming: isIncoming,
        )
    }

    func configureForRendering(conversationStyle: ConversationStyle) {
        let playbackTimeLabelConfig = Self.playbackTimeLabelConfig(isIncoming: isIncoming)
        playbackTimeLabelConfig.applyForRendering(label: playbackTimeLabel)
        playbackTimeLabel.setContentHuggingHigh()
    }

    func bottomSubviewGenerators(conversationStyle: ConversationStyle?) -> [SubviewGenerator] {
        struct SubviewConfig {
            var playbackTimeLabelMeasurementInfo: ManualStackSubviewInfo
            var playedDotContainerMeasurementInfo: ManualStackSubviewInfo
            var playbackRateViewMeasurementInfo: ManualStackSubviewInfo
        }
        let makeSubviewConfig = { [unowned self] (maxWidth: CGFloat) -> SubviewConfig in
            let dotSize = CGSize(square: 6)

            let playbackTimeLabelConfig = Self.playbackTimeLabelConfig_forMeasurement(
                audioAttachment: audioAttachment,
                maxWidth: maxWidth,
            )
            let playbackTimeLabelSize = CVText.measureLabel(config: playbackTimeLabelConfig, maxWidth: maxWidth)

            let playbackRateSize = AudioMessagePlaybackRateView.measure(maxWidth: maxWidth)

            return SubviewConfig(
                playbackTimeLabelMeasurementInfo: playbackTimeLabelSize.asManualSubviewInfo(hasFixedSize: true),
                playedDotContainerMeasurementInfo: dotSize.asManualSubviewInfo(hasFixedSize: true),
                playbackRateViewMeasurementInfo: playbackRateSize.asManualSubviewInfo(hasFixedSize: true),
            )
        }
        var subviewConfig: SubviewConfig?
        let lazySubviewConfig = { maxWidth in
            if let subviewConfig {
                return subviewConfig
            }
            let result = makeSubviewConfig(maxWidth)
            subviewConfig = result
            return result
        }

        return [
            SubviewGenerator(
                id: "transparentSpacer1",
                measurementInfo: { _ in CGSize.zero.asManualSubviewInfo(hasFixedWidth: true) },
                viewGenerator: { UIView.transparentSpacer() },
            ),
            SubviewGenerator(
                id: "playbackTimeLabel",
                measurementInfo: { lazySubviewConfig($0).playbackTimeLabelMeasurementInfo },
                viewGenerator: { [unowned self] in self.playbackTimeLabel },
            ),
            SubviewGenerator(
                id: "playedDotContainer",
                measurementInfo: { lazySubviewConfig($0).playedDotContainerMeasurementInfo },
                viewGenerator: { [unowned self] in self.playedDotContainer },
            ),
            SubviewGenerator(
                id: "playbackRateView",
                measurementInfo: { lazySubviewConfig($0).playbackRateViewMeasurementInfo },
                viewGenerator: { [unowned self] in self.playbackRateView },
            ),
            SubviewGenerator(
                id: "transparentSpacer2",
                measurementInfo: { _ in .empty },
                viewGenerator: { UIView.transparentSpacer() },
            ),
        ]
    }

    var topLabelConfig: CVLabelConfig? {
        guard !audioAttachment.isVoiceMessage else {
            return nil
        }

        let text: String
        if let fileName = audioAttachment.sourceFilename?.stripped, !fileName.isEmpty {
            text = fileName
        } else {
            text = OWSLocalizedString("GENERIC_ATTACHMENT_LABEL", comment: "A label for generic attachments.")
        }

        return CVLabelConfig.unstyledText(
            text,
            font: Constants.labelFont,
            textColor: ConversationStyle.bubbleTextColor(isIncoming: isIncoming),
        )
    }

    func audioWaveform(attachment: Attachment) -> Task<AudioWaveform, Error> {
        DependenciesBridge.shared.audioWaveformManager.cachedAudioWaveform(
            attachment: attachment,
        )
    }
}

private enum Constants {
    static let labelFont: UIFont = .dynamicTypeCaption2
}
