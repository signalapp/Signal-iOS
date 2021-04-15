//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging

@objc
public class CVComponentAudioAttachment: CVComponentBase, CVComponent {

    private let audioAttachment: AudioAttachment
    private var attachment: TSAttachment { audioAttachment.attachment }
    private var attachmentStream: TSAttachmentStream? { audioAttachment.attachmentStream }

    init(itemModel: CVItemModel, audioAttachment: AudioAttachment) {
        self.audioAttachment = audioAttachment

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewAudioAttachment()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewAudioAttachment else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let stackView = componentView.stackView

        owsAssertDebug(attachment.isAudio)
        // TODO: We might want to convert AudioMessageView into a form that can be reused.
        let audioMessageView = AudioMessageView(audioAttachment: audioAttachment,
                                                isIncoming: isIncoming)
        audioMessageView.configureForRendering(cellMeasurement: cellMeasurement,
                                               conversationStyle: conversationStyle)
        componentView.audioMessageView = audioMessageView
        stackView.configure(config: stackViewConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_stackView,
                            subviews: [ audioMessageView ])
    }

    private var stackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private static let measurementKey_stackView = "CVComponentAudioAttachment.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let audioSize = AudioMessageView.measure(maxWidth: maxWidth,
                                                 audioAttachment: audioAttachment,
                                                 isIncoming: isIncoming,
                                                 conversationStyle: conversationStyle,
                                                 measurementBuilder: measurementBuilder).ceil
        let audioInfo = audioSize.asManualSubviewInfo
        let stackMeasurement = ManualStackView.measure(config: stackViewConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_stackView,
                                                       subviewInfos: [ audioInfo ])
        var measuredSize = stackMeasurement.measuredSize
        measuredSize.width = maxWidth
        return measuredSize
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let attachmentStream = attachmentStream else {
            return false
        }
        cvAudioPlayer.togglePlayState(forAttachmentStream: attachmentStream)
        return true
    }

    // MARK: - Scrub Audio With Pan

    public override func findPanHandler(sender: UIPanGestureRecognizer,
                                        componentDelegate: CVComponentDelegate,
                                        componentView: CVComponentView,
                                        renderItem: CVRenderItem,
                                        messageSwipeActionState: CVMessageSwipeActionState) -> CVPanHandler? {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewAudioAttachment else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        guard componentDelegate.cvc_shouldAllowReplyForItem(itemViewModel) else {
            return nil
        }
        guard nil != attachmentStream else {
            return nil
        }
        guard let audioMessageView = componentView.audioMessageView else {
            owsFailDebug("Missing audioMessageView.")
            return nil
        }
        let location = sender.location(in: audioMessageView)
        guard audioMessageView.isPointInScrubbableRegion(location) else {
            return nil
        }

        return CVPanHandler(delegate: componentDelegate,
                            panType: .scrubAudio,
                            renderItem: renderItem)
    }

    public override func startPanGesture(sender: UIPanGestureRecognizer,
                                         panHandler: CVPanHandler,
                                         componentDelegate: CVComponentDelegate,
                                         componentView: CVComponentView,
                                         renderItem: CVRenderItem,
                                         messageSwipeActionState: CVMessageSwipeActionState) {
        AssertIsOnMainThread()
    }

    public override func handlePanGesture(sender: UIPanGestureRecognizer,
                                          panHandler: CVPanHandler,
                                          componentDelegate: CVComponentDelegate,
                                          componentView: CVComponentView,
                                          renderItem: CVRenderItem,
                                          messageSwipeActionState: CVMessageSwipeActionState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewAudioAttachment else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        guard let audioMessageView = componentView.audioMessageView else {
            owsFailDebug("Missing audioMessageView.")
            return
        }
        let location = sender.location(in: audioMessageView)
        guard let attachmentStream = attachmentStream else {
            return
        }
        switch sender.state {
        case .changed:
            let progress = audioMessageView.progressForLocation(location)
            audioMessageView.setOverrideProgress(progress, animated: false)
        case .ended:
            // Only update the actual playback position when the user finishes scrubbing,
            // we still call `scrubToLocation` above in order to update the slider.
            audioMessageView.clearOverrideProgress(animated: false)
            let scrubbedTime = audioMessageView.scrubToLocation(location)
            cvAudioPlayer.setPlaybackProgress(progress: scrubbedTime,
                                            forAttachmentStream: attachmentStream)
            if cvAudioPlayer.audioPlaybackState(forAttachmentId: attachmentStream.uniqueId) != .playing {
                cvAudioPlayer.togglePlayState(forAttachmentStream: attachmentStream)
            }
        case .possible, .began, .failed, .cancelled:
            audioMessageView.clearOverrideProgress(animated: false)
        @unknown default:
            owsFailDebug("Invalid state.")
            audioMessageView.clearOverrideProgress(animated: false)
        }
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewAudioAttachment: NSObject, CVComponentView {

        fileprivate let stackView = ManualStackView(name: "CVComponentViewAudioAttachment.stackView")

        fileprivate var audioMessageView: AudioMessageView?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            stackView.reset()

            audioMessageView?.removeFromSuperview()
            audioMessageView = nil
        }
    }
}

// MARK: -

extension CVComponentAudioAttachment: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        if attachment.isVoiceMessage {
            if let attachmentStream = attachmentStream,
               attachmentStream.audioDurationSeconds() > 0 {
                let format = NSLocalizedString("ACCESSIBILITY_LABEL_VOICE_MEMO_FORMAT",
                                               comment: "Accessibility label for a voice memo. Embeds: {{ the duration of the voice message }}.")
                let duration = OWSFormat.formatInt(Int(attachmentStream.audioDurationSeconds()))
                return String(format: format, duration)
            } else {
                return NSLocalizedString("ACCESSIBILITY_LABEL_VOICE_MEMO",
                                         comment: "Accessibility label for a voice memo.")
            }
        } else {
            // TODO: We could include information about the attachment format.
            return NSLocalizedString("ACCESSIBILITY_LABEL_AUDIO",
                                     comment: "Accessibility label for audio.")
        }
    }
}
