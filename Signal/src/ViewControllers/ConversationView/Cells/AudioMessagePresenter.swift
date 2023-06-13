//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import SignalUI
import UIKit

// Defines the look of audio messages in the conversation view.
class AudioMessagePresenter: AudioPresenter {
    let name = "AudioMessageView"
    let isIncoming: Bool
    let playbackTimeLabel = CVLabel()
    let playedDotContainer = ManualLayoutView(name: "playedDotContainer")
    let playbackRateView: AudioMessagePlaybackRateView
    let audioAttachment: AudioAttachment
    let threadUniqueId: String
    let audioPlaybackRate: AudioPlaybackRate

    init(isIncoming: Bool,
         audioAttachment: AudioAttachment,
         threadUniqueId: String,
         playbackRate: AudioPlaybackRate) {
        self.threadUniqueId = threadUniqueId
        self.audioPlaybackRate = playbackRate
        self.isIncoming = isIncoming
        self.audioAttachment = audioAttachment
        self.playbackRateView = AudioMessagePlaybackRateView(
            threadUniqueId: threadUniqueId,
            audioAttachment: audioAttachment,
            playbackRate: playbackRate,
            isIncoming: isIncoming)
    }

    var bottomInnerStackSpacing: CGFloat {
        switch UIApplication.shared.preferredContentSizeCategory {
        case .extraSmall, .small, .medium, .large, .extraLarge:
            return 8
        default:
            return 4
        }
    }

    func playedColor(isIncoming: Bool) -> UIColor {
        return isIncoming ? (Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray60)
        : .ows_white
    }

    func unplayedColor(isIncoming: Bool) -> UIColor {
        return isIncoming ? (Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray25) : .ows_whiteAlpha40

    }
    func thumbColor(isIncoming: Bool) -> UIColor {
        return playedColor(isIncoming: isIncoming)
    }

    func playPauseContainerBackgroundColor(isIncoming: Bool) -> UIColor {
        return isIncoming ? (Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_whiteAlpha80) : .ows_whiteAlpha20
    }

    func playPauseAnimationColor(isIncoming: Bool) -> ColorValueProvider {
        ColorValueProvider(thumbColor(isIncoming: isIncoming).lottieColorValue)
    }

    func playedDotAnimationColor(conversationStyle: ConversationStyle,
                                 isIncoming: Bool) -> ColorValueProvider {
        return ColorValueProvider(conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming).lottieColorValue)
    }

    func configureForRendering(conversationStyle: ConversationStyle) {
        let playbackTimeLabelConfig = playbackTimeLabelConfig_render(
            isIncoming: isIncoming,
            conversationStyle: conversationStyle)
        playbackTimeLabelConfig.applyForRendering(label: playbackTimeLabel)
        playbackTimeLabel.setContentHuggingHigh()
    }

    func bottomSubviewGenerators(conversationStyle: ConversationStyle) -> [SubviewGenerator] {
        struct SubviewConfig {
            var playbackTimeLabelMeasurementInfo: ManualStackSubviewInfo
            var playedDotContainerMeasurementInfo: ManualStackSubviewInfo
            var playbackRateViewMeasurementInfo: ManualStackSubviewInfo
        }
        let makeSubviewConfig = { [unowned self] (maxWidth: CGFloat) -> SubviewConfig in
            let dotSize = CGSize(square: 6)

            let playbackTimeLabelConfig = playbackTimeLabelConfig_forMeasurement(
                audioAttachment: audioAttachment,
                isIncoming: isIncoming,
                conversationStyle: conversationStyle,
                maxWidth: maxWidth
            )
            let playbackTimeLabelSize = CVText.measureLabel(config: playbackTimeLabelConfig, maxWidth: maxWidth)

            let playbackRateSize = AudioMessagePlaybackRateView.measure(maxWidth: maxWidth)

            return SubviewConfig(
                playbackTimeLabelMeasurementInfo: playbackTimeLabelSize.asManualSubviewInfo(hasFixedSize: true),
                playedDotContainerMeasurementInfo: dotSize.asManualSubviewInfo(hasFixedSize: true),
                playbackRateViewMeasurementInfo: playbackRateSize.asManualSubviewInfo(hasFixedSize: true))
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
                viewGenerator: { UIView.transparentSpacer() }),
            SubviewGenerator(
                id: "playbackTimeLabel",
                measurementInfo: { lazySubviewConfig($0).playbackTimeLabelMeasurementInfo },
                viewGenerator: { [unowned self] in self.playbackTimeLabel }),
            SubviewGenerator(
                id: "playedDotContainer",
                measurementInfo: { lazySubviewConfig($0).playedDotContainerMeasurementInfo },
                viewGenerator: { [unowned self] in self.playedDotContainer }),
            SubviewGenerator(
                id: "playbackRateView",
                measurementInfo: { lazySubviewConfig($0).playbackRateViewMeasurementInfo },
                viewGenerator: { [unowned self] in self.playbackRateView}),
            SubviewGenerator(
                id: "transparentSpacer2",
                measurementInfo: { _ in .empty },
                viewGenerator: { UIView.transparentSpacer() })
        ]
    }
    func topLabelConfig(audioAttachment: AudioAttachment,
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
            text = OWSLocalizedString("GENERIC_ATTACHMENT_LABEL", comment: "A label for generic attachments.")
        }

        return CVLabelConfig(
            text: text,
            font: Constants.labelFont,
            textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming))
    }

    func audioWaveform(attachmentStream: TSAttachmentStream?) -> AudioWaveform? {
        return attachmentStream?.audioWaveform()
    }
}

private enum Constants {
    static let labelFont: UIFont = .dynamicTypeCaption2
}
