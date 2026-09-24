//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

struct SubviewGenerator {
    var id: String
    var measurementInfo: (CGFloat) -> ManualStackSubviewInfo
    var viewGenerator: () -> UIView
}

// To make a custom audio message view, implement this protocol and give it to
// AudioMessageView's initializer.
protocol AudioPresenter {
    // This is used for debugging. The name is given to the root ManualStackView.
    var name: String { get }

    // Thread for the message.
    var threadUniqueId: String { get }

    // A playable audio attachemnt.
    var audioAttachment: AudioAttachment { get }

    // Defines and stores the speed of playback.
    var audioPlaybackRate: AudioPlaybackRate { get }

    // Color for play/pause button.
    func playPauseAnimationColor() -> UIColor

    // Color for dot indicating listened/unlistened status.
    func playedDotAnimationColor(conversationStyle: ConversationStyle) -> UIColor

    // Color for the scrubbing thumb drawn over the waveform.
    func waveformThumbColor() -> UIColor

    // Color for the scrubbing thumb on the progress bar shown when there's no
    // waveform to draw.
    func progressBarThumbColor() -> UIColor

    // Color for the progress bar left of the thumb.
    func playedColor() -> UIColor

    // Color for the progress bar right of the thumb.
    func unplayedColor() -> UIColor

    // Color of circle enclosing the play/pause icon.
    func playPauseContainerBackgroundColor(conversationStyle: ConversationStyle) -> UIColor

    // Configuration for the progress view shown in place of the play/pause
    // button while the attachment is undownloaded.
    func progressViewConfiguration(conversationStyle: ConversationStyle) -> CVAttachmentProgressView.Configuration

    // Last chance to adjust constraints before the view appears.
    func configureForRendering(conversationStyle: ConversationStyle)

    // Views to show beneath the play/pause button and waveform.
    func bottomSubviewGenerators(conversationStyle: ConversationStyle?) -> [SubviewGenerator]

    // Label that shows the duration remaining.
    var playbackTimeLabel: CVLabel { get }

    // View that shows the speed of playback.
    var playbackRateView: AudioMessagePlaybackRateView { get }

    // View that indicates whether the audio has already been listened to.
    var playedDotContainer: ManualLayoutView { get }

    // Horizontal sSpace between the bottom inner subviews.
    var bottomInnerStackSpacing: CGFloat { get }

    // If you want to show a label at the top of the view, return its configuration here.
    // For example, you could choose to show a filename when one exists.
    var topLabelConfig: CVLabelConfig? { get }

    // The sampled waveform used to display the visual preview of the audio
    // message. Fails if it doesn't have one.
    func audioWaveform(attachment: Attachment) -> Task<AudioWaveform, Error>
}

extension AudioPresenter {

    static func playbackTimeLabelConfig_forMeasurement(audioAttachment: AudioAttachment, maxWidth: CGFloat) -> CVLabelConfig {
        // playbackTimeLabel uses a monospace font, so we measure the
        // worst-case width using the full duration of the audio.
        let text = OWSFormat.localizedDurationString(from: audioAttachment.durationSeconds ?? 0)
        let fullDurationConfig = playbackTimeLabelConfig(text: text)
        // Never let it get shorter than "0:00" duration.
        let minimumWidthText = OWSFormat.localizedDurationString(from: 0)
        let minimumWidthConfig = playbackTimeLabelConfig(text: minimumWidthText)
        if minimumWidthConfig.measure(maxWidth: maxWidth).width > fullDurationConfig.measure(maxWidth: maxWidth).width {
            return minimumWidthConfig
        } else {
            return fullDurationConfig
        }
    }

    static func playbackTimeLabelConfig(text: String = " ", isIncoming: Bool = true) -> CVLabelConfig {
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeCaption1Clamped,
            textColor: isIncoming ? .Signal.secondaryLabel : .Signal.ColorBase.labelSecondary,
        )
    }
}
