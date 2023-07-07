//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

class AudioAllMediaPresenter: AudioPresenter {
    private enum Constants {
        static let filenameFont: UIFont = .dynamicTypeCaption1
        static let bottomLineFont: UIFont = .dynamicTypeFootnoteClamped

        static var bottomInnerStackSpacing: CGFloat {
            switch UIApplication.shared.preferredContentSizeCategory {
            case .extraSmall, .small, .medium, .large, .extraLarge:
                return 8
            default:
                return 4
            }
        }
    }

    let name = "AudioAllMedia"
    let isIncoming = false

    let sender: String
    let size: String
    let date: String

    let playbackTimeLabel = CVLabel()
    let playedDotContainer = ManualLayoutView(name: "playedDotContainer")
    let playbackRateView: AudioMessagePlaybackRateView
    let senderLabel = CVLabel()
    let sizeLabel = CVLabel()
    let dateLabel = CVLabel()
    let dot1 = CVLabel()
    let dot2 = CVLabel()

    private static let middleDot = " · "
    func playedColor(isIncoming: Bool ) -> UIColor {
        return Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray90
    }
    func unplayedColor(isIncoming: Bool) -> UIColor {
        return Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray20
    }
    func thumbColor(isIncoming: Bool) -> UIColor {
        return playedColor(isIncoming: isIncoming)
    }
    func playPauseContainerBackgroundColor(isIncoming: Bool) -> UIColor {
        return Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
    }

    func playPauseAnimationColor(isIncoming: Bool) -> ColorValueProvider {
        let color = playedColor(isIncoming: isIncoming)
        return ColorValueProvider(color.lottieColorValue)
    }

    func playedDotAnimationColor(conversationStyle: ConversationStyle, isIncoming: Bool) -> ColorValueProvider {
        return ColorValueProvider(conversationStyle.bubbleSecondaryTextColor(isIncoming: true).lottieColorValue)
    }
    var bottomInnerStackSpacing: CGFloat { 0 }

    let audioAttachment: AudioAttachment
    let threadUniqueId: String
    let audioPlaybackRate: AudioPlaybackRate

    init(
        sender: String,
        audioAttachment: AudioAttachment,
        threadUniqueId: String,
        playbackRate: AudioPlaybackRate,
        isIncoming: Bool
    ) {
        self.threadUniqueId = threadUniqueId
        self.sender = sender
        self.audioPlaybackRate = playbackRate
        self.audioAttachment = audioAttachment
        self.size = audioAttachment.sizeString
        self.date = audioAttachment.dateString
        playbackRateView = AllMediaAudioMessagePlaybackRateView(
            threadUniqueId: threadUniqueId,
            audioAttachment: audioAttachment,
            playbackRate: playbackRate,
            isIncoming: isIncoming
        )
    }

    func configureForRendering(conversationStyle: ConversationStyle) {
        let playbackTimeLabelConfig = playbackTimeLabelConfig_render(
            isIncoming: isIncoming,
            conversationStyle: conversationStyle)
        playbackTimeLabelConfig.applyForRendering(label: playbackTimeLabel)
        playbackTimeLabel.setContentHuggingHigh()

        let senderLabelConfig = Self.labelConfig_render(
            text: sender,
            lineBreakMode: .byTruncatingTail,
            conversationStyle: conversationStyle)
        let sizeLabelConfig = Self.labelConfig_render(text: size, conversationStyle: conversationStyle)
        let dateLabelConfig = Self.labelConfig_render(text: date, conversationStyle: conversationStyle)
        let dot1Config = Self.labelConfig_render(text: AudioAllMediaPresenter.middleDot, conversationStyle: conversationStyle)
        let dot2Config = Self.labelConfig_render(text: AudioAllMediaPresenter.middleDot, conversationStyle: conversationStyle)
        senderLabelConfig.applyForRendering(label: senderLabel)
        senderLabel.setContentHuggingHigh()

        sizeLabelConfig.applyForRendering(label: sizeLabel)
        sizeLabel.setContentHuggingHigh()

        dateLabelConfig.applyForRendering(label: dateLabel)
        dateLabel.setContentHuggingHigh()

        dot1Config.applyForRendering(label: dot1)
        dot1.setContentHuggingHigh()

        dot2Config.applyForRendering(label: dot2)
        dot2.setContentHuggingHigh()
    }

    private static func labelConfig_render(
        text: String,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        conversationStyle: ConversationStyle
    ) -> CVLabelConfig {
        return CVLabelConfig.unstyledText(
            text,
            font: Constants.bottomLineFont,
            textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: true),
            lineBreakMode: lineBreakMode
        )
    }

    private var subviews: Subviews {
        Subviews(
            playedDotContainer: playedDotContainer,
            playbackTimeLabel: playbackTimeLabel,
            playbackRateView: playbackRateView,
            senderLabel: senderLabel,
            sizeLabel: sizeLabel,
            dateLabel: dateLabel,
            dot1: dot1,
            dot2: dot2
        )
    }

    var bottomSubviews: [UIView] {
        let subviews = self.subviews
        return Self.bottomViewsWithSizingInfo.map { $0.view(subviews) }
    }

    private struct Subviews {
        var playedDotContainer: UIView
        var playbackTimeLabel: UIView
        var playbackRateView: UIView
        var senderLabel: UIView
        var sizeLabel: UIView
        var dateLabel: UIView
        var dot1: UIView
        var dot2: UIView
    }

    private struct SubviewConfig {
        var dotSize: CGSize
        var maxWidth: CGFloat
        var playbackTimeLabelSize: CGSize
        var playbackRateSize: CGSize
        var senderSize: CGSize
        var sizeSize: CGSize
        var dateSize: CGSize
        var dot1Size: CGSize
        var dot2Size: CGSize
    }

    private struct ViewWithSizingInfo {
        var id: String
        var view: (Subviews) -> (UIView)
        var subviewInfo: (SubviewConfig) -> (ManualStackSubviewInfo)
        var shouldAddSubview: Bool
    }

    private static var bottomViewsWithSizingInfo: [ViewWithSizingInfo] = {
        return [
            ViewWithSizingInfo(
                id: "senderLabel",
                view: { $0.senderLabel },
                subviewInfo: { $0.senderSize.asManualSubviewInfo(hasFixedSize: true) },
                shouldAddSubview: true),
            ViewWithSizingInfo(
                id: "dot1",
                view: { $0.dot1 },
                subviewInfo: { $0.dot1Size.asManualSubviewInfo(hasFixedSize: true) },
                shouldAddSubview: true),
            ViewWithSizingInfo(
                id: "sizeLabel",
                view: { $0.sizeLabel },
                subviewInfo: { $0.sizeSize.asManualSubviewInfo(hasFixedSize: true) },
                shouldAddSubview: true),
            ViewWithSizingInfo(
                id: "dot2",
                view: { $0.dot2 },
                subviewInfo: { $0.dot2Size.asManualSubviewInfo(hasFixedSize: true) },
                shouldAddSubview: true),
            ViewWithSizingInfo(
                id: "dateLabel",
                view: { $0.dateLabel },
                subviewInfo: { $0.dateSize.asManualSubviewInfo(hasFixedSize: true) },
                shouldAddSubview: true),
            ViewWithSizingInfo(
                id: "hStretchingSpacer",
                view: { _ in .hStretchingSpacer() },
                subviewInfo: { _ in .empty },
                shouldAddSubview: false),
            ViewWithSizingInfo(
                id: "transparentSpacer1",
                view: { _ in UIView.transparentSpacer() },
                subviewInfo: { _ in
                    CGSize(width: Constants.bottomInnerStackSpacing,
                           height: 0).asManualSubviewInfo(hasFixedSize: true)
                },
                shouldAddSubview: false),
            ViewWithSizingInfo(
                id: "playbackTimeLabel",
                view: { $0.playbackTimeLabel },
                subviewInfo: { $0.playbackTimeLabelSize.asManualSubviewInfo(hasFixedSize: true) },
                shouldAddSubview: true),
            ViewWithSizingInfo(
                id: "transparentSpacer2",
                view: { _ in UIView.transparentSpacer() },
                subviewInfo: { _ in
                    CGSize(
                        width: Constants.bottomInnerStackSpacing,
                        height: 0).asManualSubviewInfo(hasFixedSize: true)
                },
                shouldAddSubview: false),
            ViewWithSizingInfo(
                id: "playbackRateView",
                view: { $0.playbackRateView },
                subviewInfo: { $0.playbackRateSize.asManualSubviewInfo(hasFixedSize: true) },
                shouldAddSubview: true),
            ViewWithSizingInfo(
                id: "playedDotContainer",
                view: { $0.playedDotContainer },
                subviewInfo: { $0.dotSize.asManualSubviewInfo(hasFixedSize: true) },
                shouldAddSubview: true)
        ]
    }()

    func bottomSubviewGenerators(conversationStyle: ConversationStyle) -> [SubviewGenerator] {
        let makeSubviewConfig = { [unowned self] (maxWidth: CGFloat) -> SubviewConfig in
            let playbackTimeLabelConfig = playbackTimeLabelConfig_forMeasurement(
                audioAttachment: audioAttachment,
                isIncoming: isIncoming,
                conversationStyle: conversationStyle,
                maxWidth: maxWidth
            )
            let playbackTimeLabelSize = CVText.measureLabel(config: playbackTimeLabelConfig, maxWidth: maxWidth)

            let senderLabelConfig = labelConfig_forMeasurement(
                text: sender,
                conversationStyle: conversationStyle)
            let sizeLabelConfig = labelConfig_forMeasurement(
                text: audioAttachment.sizeString,
                conversationStyle: conversationStyle)
            let dateLabelConfig = labelConfig_forMeasurement(
                text: audioAttachment.dateString,
                conversationStyle: conversationStyle)
            let dot1Config = labelConfig_forMeasurement(
                text: AudioAllMediaPresenter.middleDot,
                conversationStyle: conversationStyle)
            let dot2Config = labelConfig_forMeasurement(
                text: AudioAllMediaPresenter.middleDot,
                conversationStyle: conversationStyle)

            var senderSize = CVText.measureLabel(config: senderLabelConfig, maxWidth: maxWidth)
            senderSize.width = min(senderSize.width, round(maxWidth * 0.33))
            let sizeSize = CVText.measureLabel(config: sizeLabelConfig, maxWidth: maxWidth)
            let dateSize = CVText.measureLabel(config: dateLabelConfig, maxWidth: maxWidth)
            let dot1Size = CVText.measureLabel(config: dot1Config, maxWidth: maxWidth)
            let dot2Size = CVText.measureLabel(config: dot2Config, maxWidth: maxWidth)
            let playbackRateSize = AudioMessagePlaybackRateView.measure(maxWidth: maxWidth)

            let dotSize = CGSize(square: 6)
            let subviewConfig = SubviewConfig(
                dotSize: dotSize,
                maxWidth: maxWidth,
                playbackTimeLabelSize: playbackTimeLabelSize,
                playbackRateSize: playbackRateSize,
                senderSize: senderSize,
                sizeSize: sizeSize,
                dateSize: dateSize,
                dot1Size: dot1Size,
                dot2Size: dot2Size)
            return subviewConfig
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
        return Self.bottomViewsWithSizingInfo.map { [unowned self] vwsi in
            return SubviewGenerator(
                id: vwsi.id,
                measurementInfo: { vwsi.subviewInfo(lazySubviewConfig($0)) },
                viewGenerator: { vwsi.view(self.subviews) })
        }
    }

    private func labelConfig_forMeasurement(
        text: String,
        conversationStyle: ConversationStyle
    ) -> CVLabelConfig {
        return CVLabelConfig.unstyledText(
            text,
            font: Constants.bottomLineFont,
            textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: true)
        )
    }

    static func hasAttachmentLabel(attachment: TSAttachment) -> Bool {
        return !attachment.isVoiceMessage
    }

    func hasAttachmentLabel(attachment: TSAttachment) -> Bool {
        return Self.hasAttachmentLabel(attachment: attachment)
    }

    func topLabelConfig(
        audioAttachment: AudioAttachment,
        isIncoming: Bool,
        conversationStyle: ConversationStyle
    ) -> CVLabelConfig? {

        let attachment = audioAttachment.attachment
        guard hasAttachmentLabel(attachment: attachment) else {
            return nil
        }

        let text: String
        if let fileName = attachment.sourceFilename?.stripped, !fileName.isEmpty {
            text = fileName
        } else {
            text = NSLocalizedString("GENERIC_ATTACHMENT_LABEL", comment: "A label for generic attachments.")
        }

        return CVLabelConfig.unstyledText(
            text,
            font: Constants.filenameFont,
            textColor: conversationStyle.bubbleTextColor(isIncoming: false))
    }

    func audioWaveform(attachmentStream: TSAttachmentStream?) -> AudioWaveform? {
        return attachmentStream?.highPriorityAudioWaveform()
    }

}

class AllMediaAudioMessagePlaybackRateView: AudioMessagePlaybackRateView {
    override func makeBackgroundColor() -> UIColor {
        return (Theme.isDarkThemeEnabled ? UIColor.ows_white : .ows_black).withAlphaComponent(0.08)
    }
    override func makeTextColor() -> UIColor {
        return Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray60
    }
}
