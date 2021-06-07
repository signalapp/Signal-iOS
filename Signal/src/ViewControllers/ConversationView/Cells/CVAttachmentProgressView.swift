//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

// A view for presenting attachment upload/download/failure/pending state.
@objc
public class CVAttachmentProgressView: ManualLayoutView {

    public enum Direction {
        case upload(attachmentStream: TSAttachmentStream)
        case download(attachmentPointer: TSAttachmentPointer)

        var attachmentId: String {
            switch self {
            case .upload(let attachmentStream):
                return attachmentStream.uniqueId
            case .download(let attachmentPointer):
                return attachmentPointer.uniqueId
            }
        }
    }

    private static let overlayCircleSize: CGFloat = 44

    // The progress views have two styles:
    //
    // * Light on dark circle, overlaid over media.
    //   This style has a fixed size.
    // * Theme colors.
    //   This style can be embedded with other content within a message bubble.
    public enum Style {
        case withCircle
        case withoutCircle(diameter: CGFloat)

        var outerDiameter: CGFloat {
            switch self {
            case .withCircle:
                return CVAttachmentProgressView.overlayCircleSize
            case .withoutCircle(let diameter):
                return diameter
            }
        }
    }

    private let direction: Direction
    private let style: Style
    private let conversationStyle: ConversationStyle

    private let stateView: StateView

    private var attachmentId: String { direction.attachmentId }

    public required init(direction: Direction, style: Style, conversationStyle: ConversationStyle) {
        self.direction = direction
        self.style = style
        self.conversationStyle = conversationStyle
        self.stateView = StateView(diameter: Self.innerDiameter(style: style),
                                   direction: direction,
                                   style: style,
                                   conversationStyle: conversationStyle)

        super.init(name: "CVAttachmentProgressView")

        createViews()

        configureState()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    @objc
    public required init(name: String) {
        notImplemented()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private static func outerDiameter(style: Style) -> CGFloat {
        switch style {
        case .withCircle:
            return 44
        case .withoutCircle(let diameter):
            return diameter
        }
    }

    private static func innerDiameter(style: Style) -> CGFloat {
        switch style {
        case .withCircle:
            return 32
        case .withoutCircle(let diameter):
            return diameter
        }
    }

    private enum State: Equatable {
        case none
        case tapToDownload
        case downloadFailed
        case downloadUnknownProgress
        case uploadUnknownProgress
        case downloadProgress(progress: CGFloat)
        case uploadProgress(progress: CGFloat)

        var debugDescription: String {
            switch self {
            case .none:
                return "none"
            case .tapToDownload:
                return "tapToDownload"
            case .downloadFailed:
                return "downloadFailed"
            case .downloadUnknownProgress:
                return "downloadUnknownProgress"
            case .uploadUnknownProgress:
                return "uploadUnknownProgress"
            case .downloadProgress(let progress):
                return "downloadProgress: \(progress)"
            case .uploadProgress(let progress):
                return "uploadProgress: \(progress)"
            }
        }
    }

    private class StateView: ManualLayoutView {
        private let diameter: CGFloat
        private let direction: Direction
        private let style: Style
        private let conversationStyle: ConversationStyle
        private lazy var imageView = CVImageView()
        private var unknownProgressView: Lottie.AnimationView?
        private var progressView: Lottie.AnimationView?
        private lazy var outerCircleView = CVImageView()

        var state: State = .none {
            didSet {
                if oldValue != state {
                    applyState(oldState: oldValue, newState: state)
                }
            }
        }

        private var isDarkThemeEnabled: Bool { conversationStyle.isDarkThemeEnabled }
        private var isIncoming: Bool {
            switch direction {
            case .upload:
                return false
            case .download:
                return true
            }
        }

        required init(diameter: CGFloat, direction: Direction, style: Style, conversationStyle: ConversationStyle) {
            self.diameter = diameter
            self.direction = direction
            self.style = style
            self.conversationStyle = conversationStyle

            super.init(name: "CVAttachmentProgressView.StateView")

            applyState(oldState: .none, newState: .none)
        }

        @available(*, unavailable, message: "use other constructor instead.")
        @objc
        public required init(name: String) {
            notImplemented()
        }

        private func applyState(oldState: State, newState: State) {

            switch newState {
            case .none:
                reset()
            case .tapToDownload:
                if oldState != newState {
                    presentIcon(templateName: "arrow-down-24",
                                sizeInsideCircle: 16,
                                isInsideProgress: false,
                                showOuterCircleIfNecessary: true)
                }
            case .downloadFailed:
                if oldState != newState {
                    presentIcon(templateName: "retry-alt-24",
                                sizeInsideCircle: 18,
                                isInsideProgress: false,
                                showOuterCircleIfNecessary: true)
                }
            case .downloadProgress(let progress):
                switch oldState {
                case .downloadProgress:
                    updateProgress(progress: progress)
                default:
                    presentProgress(progress: progress)
                    presentIcon(templateName: "stop-20",
                                sizeInsideCircle: 16,
                                isInsideProgress: true)
                }
            case .uploadProgress(let progress):
                switch oldState {
                case .uploadProgress:
                    updateProgress(progress: progress)
                default:
                    presentProgress(progress: progress)
                }
            case .downloadUnknownProgress:
                presentUnknownProgress()
                presentIcon(templateName: "stop-20",
                            sizeInsideCircle: 10,
                            isInsideProgress: true)
            case .uploadUnknownProgress:
                presentUnknownProgress()
            }
        }

        private func presentIcon(templateName: String,
                                 sizeInsideCircle: CGFloat,
                                 isInsideProgress: Bool,
                                 showOuterCircleIfNecessary: Bool = false) {
            if !isInsideProgress {
                reset()
            }

            let iconSize: CGFloat
            let tintColor: UIColor
            let hasOuterCircle: Bool
            switch style {
            case .withCircle:
                hasOuterCircle = false
                tintColor = .ows_white
                owsAssertDebug(sizeInsideCircle < diameter)
                iconSize = sizeInsideCircle
            case .withoutCircle:
                hasOuterCircle = showOuterCircleIfNecessary
                tintColor = Theme.primaryTextColor
                // The icon size hint (sizeInsideCircle) is the size
                // in the "circle" style.  We can determine the size
                // in the "no-circle" style by multiplying by the
                // ratio between the "no-circle" diameter and the
                // "circle" diameter.
                iconSize = sizeInsideCircle * diameter / CVAttachmentProgressView.outerDiameter(style: style)
            }
            imageView.setTemplateImageName(templateName, tintColor: tintColor)
            addSubviewToCenterOnSuperview(imageView, size: .square(iconSize))

            if hasOuterCircle {
                let imageName: String
                if isDarkThemeEnabled || !isIncoming {
                    imageName = "circle_outgoing_white_40"
                } else {
                    imageName = "circle_incoming_grey_40"
                }
                outerCircleView.setImage(imageName: imageName)
                addSubviewToFillSuperviewEdges(outerCircleView)
            }
        }

        private func presentProgress(progress: CGFloat) {
            reset()

            let animationName: String
            switch style {
            case .withCircle:
                animationName = "determinate_spinner_white"
            case .withoutCircle:
                animationName = (isIncoming && !isDarkThemeEnabled
                                    ? "determinate_spinner_blue"
                                    : "determinate_spinner_white")
            }
            let animationView = ensureAnimationView(progressView, animationName: animationName)
            owsAssertDebug(animationView.animation != nil)
            progressView = animationView
            animationView.backgroundBehavior = .pause
            animationView.loopMode = .playOnce
            animationView.contentMode = .scaleAspectFit
            // We DO NOT play this animation; we "scrub" it to reflect
            // attachment upload/download progress.
            updateProgress(progress: progress)
            addSubviewToFillSuperviewEdges(animationView)
        }

        private func presentUnknownProgress() {
            reset()

            let animationName: String
            switch style {
            case .withCircle:
                animationName = "indeterminate_spinner_white"
            case .withoutCircle:
                animationName = (isIncoming && !isDarkThemeEnabled
                                    ? "indeterminate_spinner_blue"
                                    : "indeterminate_spinner_white")
            }
            let animationView = ensureAnimationView(unknownProgressView, animationName: animationName)
            owsAssertDebug(animationView.animation != nil)
            unknownProgressView = animationView
            animationView.backgroundBehavior = .pauseAndRestore
            animationView.loopMode = .loop
            animationView.contentMode = .scaleAspectFit
            animationView.play()

            addSubviewToFillSuperviewEdges(animationView)
        }

        private func ensureAnimationView(_ animationView: Lottie.AnimationView?,
                                         animationName: String) -> AnimationView {
            if let animationView = animationView {
                return animationView
            } else {
                let animationView = AnimationView(name: animationName)
                return animationView
            }
        }

        private func updateProgress(progress: CGFloat) {
            guard let progressView = progressView else {
                owsFailDebug("Missing progressView.")
                return
            }
            guard let animation = progressView.animation else {
                owsFailDebug("Missing animation.")
                return
            }

            // We DO NOT play this animation; we "scrub" it to reflect
            // attachment upload/download progress.
            progressView.currentFrame = progress.lerp(animation.startFrame,
                                                      animation.endFrame)
        }

        public override func reset() {
            super.reset()

            progressView?.stop()
            unknownProgressView?.stop()
            outerCircleView.image = nil
            imageView.image = nil
        }
    }

    private func createViews() {
        let innerContentView = self.stateView

        switch style {
        case .withCircle:
            let circleView = ManualLayoutView.circleView(name: "circleView")
            circleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.7)
            circleView.addSubviewToCenterOnSuperview(innerContentView,
                                                     size: .square(Self.outerDiameter(style: style)))
            addSubviewToFillSuperviewEdges(circleView)
        case .withoutCircle:
            addSubviewToFillSuperviewEdges(innerContentView)
        }
    }

    public var layoutSize: CGSize {
        switch style {
        case .withCircle:
            return .square(Self.outerDiameter(style: style))
        case .withoutCircle:
            return .square(Self.innerDiameter(style: style))
        }
    }

    private func configureState() {
        switch direction {
        case .upload(let attachmentStream):
            stateView.state = .uploadUnknownProgress

            updateUploadProgress(attachmentStream: attachmentStream)

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(processUploadNotification(notification:)),
                                                   name: .attachmentUploadProgress,
                                                   object: nil)

        case .download(let attachmentPointer):
            switch attachmentPointer.state {
            case .failed:
                stateView.state = .downloadFailed
            case .pendingMessageRequest, .pendingManualDownload:
                stateView.state = .tapToDownload
            case .enqueued, .downloading:
                updateDownloadProgress()

                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(processDownloadNotification(notification:)),
                                                       name: OWSAttachmentDownloads.attachmentDownloadProgressNotification,
                                                       object: nil)
            @unknown default:
                owsFailDebug("Invalid value.")
            }
        }
    }

    @objc
    private func processDownloadNotification(notification: Notification) {
        guard let attachmentId = notification.userInfo?[OWSAttachmentDownloads.attachmentDownloadAttachmentIDKey] as? String else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard attachmentId == self.attachmentId else {
            return
        }
        updateDownloadProgress()
    }

    private func updateDownloadProgress() {
        AssertIsOnMainThread()

        guard let progress = attachmentDownloads.downloadProgress(forAttachmentId: attachmentId) else {
            Logger.warn("No progress for attachment.")
            stateView.state = .downloadUnknownProgress
            return
        }

        updateState(downloadProgress: progress)
    }

    private func updateState(downloadProgress progress: CGFloat?) {
        guard let progress = progress else {
            stateView.state = .downloadUnknownProgress
            return
        }
        if progress.isNaN {
            owsFailDebug("Progress is nan.")
            stateView.state = .downloadUnknownProgress
        } else if progress > 0 {
            stateView.state = .downloadProgress(progress: CGFloat(progress))
        } else {
            stateView.state = .downloadUnknownProgress
        }
    }

    @objc
    private func processUploadNotification(notification: Notification) {
        guard let notificationAttachmentId = notification.userInfo?[kAttachmentUploadAttachmentIDKey] as? String else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard notificationAttachmentId == attachmentId else {
            return
        }
        guard let progress = notification.userInfo?[kAttachmentUploadProgressKey] as? NSNumber else {
            owsFailDebug("Missing progress.")
            stateView.state = .uploadUnknownProgress
            return
        }

        switch direction {
        case .upload(let attachmentStream):
            guard !attachmentStream.isUploaded else {
                stateView.state = .uploadProgress(progress: 1)
                return
            }
        case .download:
            owsFailDebug("Invalid attachment.")
            stateView.state = .uploadUnknownProgress
            return
        }

        updateState(uploadProgress: progress)
    }

    private func updateState(uploadProgress progress: NSNumber?) {
        guard let progress = progress?.floatValue else {
            stateView.state = .uploadUnknownProgress
            return
        }
        if progress.isNaN {
            owsFailDebug("Progress is nan.")
            stateView.state = .uploadUnknownProgress
        } else if progress > 0 {
            stateView.state = .uploadProgress(progress: CGFloat(progress))
        } else {
            stateView.state = .uploadUnknownProgress
        }
    }

    private func updateUploadProgress(attachmentStream: TSAttachmentStream) {
        AssertIsOnMainThread()

        if attachmentStream.isUploaded {
            stateView.state = .uploadProgress(progress: 1)
        } else {
            stateView.state = .uploadUnknownProgress
        }
    }

    public enum ProgressType {
        case none
        case uploading(attachmentStream: TSAttachmentStream)
        case pendingDownload(attachmentPointer: TSAttachmentPointer)
        case downloading(attachmentPointer: TSAttachmentPointer)
        case restoring(attachmentPointer: TSAttachmentPointer)
        case unknown
    }

    public static func progressType(forAttachment attachment: TSAttachment,
                                    interaction: TSInteraction) -> ProgressType {

        if let attachmentStream = attachment as? TSAttachmentStream {
            if let outgoingMessage = interaction as? TSOutgoingMessage {
                let hasSendFailed = outgoingMessage.messageState == .failed
                let isFromLinkedDevice = outgoingMessage.isFromLinkedDevice
                guard !attachmentStream.isUploaded,
                        !isFromLinkedDevice,
                        !hasSendFailed else {
                    return .none
                }
                return .uploading(attachmentStream: attachmentStream)
            } else if interaction is TSIncomingMessage {
                return .none
            } else {
                owsFailDebug("Unexpected interaction: \(type(of: interaction))")
                return .unknown
            }
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            guard attachmentPointer.pointerType == .incoming else {
                return .restoring(attachmentPointer: attachmentPointer)
            }
            switch attachmentPointer.state {
            case .pendingMessageRequest, .pendingManualDownload:
                return .pendingDownload(attachmentPointer: attachmentPointer)
            case .failed, .enqueued, .downloading:
                return .downloading(attachmentPointer: attachmentPointer)
            @unknown default:
                owsFailDebug("Invalid value.")
                return .unknown
            }

        } else {
            owsFailDebug("Unexpected attachment: \(type(of: attachment))")
            return .unknown
        }
    }
}
