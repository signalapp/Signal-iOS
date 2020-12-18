//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentAudioAttachment: CVComponentBase, CVComponent {

    // MARK: - Dependencies

    private var audioPlayer: CVAudioPlayer {
        return AppEnvironment.shared.audioPlayer
    }

    // MARK: -

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

        owsAssertDebug(attachment.isAudio)
        // TODO: We might want to convert AudioMessageView into a form that can be reused.
        let audioMessageView = AudioMessageView(audioAttachment: audioAttachment,
                                                isIncoming: isIncoming,
                                                conversationStyle: conversationStyle)
        componentView.audioMessageView = audioMessageView
        componentView.rootView.addSubview(audioMessageView)
        audioMessageView.autoPinEdgesToSuperviewEdges()

        let accessibilityDescription = NSLocalizedString("ACCESSIBILITY_LABEL_AUDIO",
                                                         comment: "Accessibility label for audio.")
        audioMessageView.accessibilityLabel = accessibilityLabel(description: accessibilityDescription)
    }

    public override func incompleteAttachmentInfo(componentView: CVComponentView) -> IncompleteAttachmentInfo? {
        return incompleteAttachmentInfoIfNecessary(attachment: attachment,
                                                   attachmentView: componentView.rootView)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let height = AudioMessageView.measureHeight(audioAttachment: audioAttachment,
                                                    isIncoming: isIncoming,
                                                    conversationStyle: conversationStyle)
        return CGSize(width: maxWidth, height: height).ceil
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let attachmentStream = attachmentStream else {
            return false
        }
        audioPlayer.togglePlayState(forAttachmentStream: attachmentStream)
        return true
    }

    // MARK: - Scrub Audio With Pan

    public override func findPanHandler(sender: UIPanGestureRecognizer,
                                        componentDelegate: CVComponentDelegate,
                                        componentView: CVComponentView,
                                        renderItem: CVRenderItem,
                                        swipeToReplyState: CVSwipeToReplyState) -> CVPanHandler? {
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
                                         swipeToReplyState: CVSwipeToReplyState) {
        AssertIsOnMainThread()
    }

    public override func handlePanGesture(sender: UIPanGestureRecognizer,
                                          panHandler: CVPanHandler,
                                          componentDelegate: CVComponentDelegate,
                                          componentView: CVComponentView,
                                          renderItem: CVRenderItem,
                                          swipeToReplyState: CVSwipeToReplyState) {
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
            audioPlayer.setPlaybackProgress(progress: scrubbedTime,
                                            forAttachmentStream: attachmentStream)
            if audioPlayer.audioPlaybackState(forAttachmentId: attachmentStream.uniqueId) != .playing {
                audioPlayer.togglePlayState(forAttachmentStream: attachmentStream)
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

        fileprivate let containerView = UIView.container()

        fileprivate var audioMessageView: AudioMessageView?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            containerView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            containerView.removeAllSubviews()

            audioMessageView?.removeFromSuperview()
            audioMessageView = nil
        }
    }
}
