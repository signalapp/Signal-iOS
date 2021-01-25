//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

// A view for presenting attachment upload/download/failure/pending state.
@objc
public class CVAttachmentProgressView: UIView {

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
                return 44
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

        super.init(frame: .zero)

        createViews()

        configureState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    private class StateView: UIView {
        private let diameter: CGFloat
        private let direction: Direction
        private let style: Style
        private let conversationStyle: ConversationStyle
        private lazy var imageView = UIImageView()
        private var unknownProgressView: Lottie.AnimationView?
        private var progressView: Lottie.AnimationView?

        private var layoutConstraints = [NSLayoutConstraint]()

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

            super.init(frame: .zero)

            applyState(oldState: .none, newState: .none)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func applyState(oldState: State, newState: State) {

            switch newState {
            case .none:
                reset()
            case .tapToDownload:
                if oldState != newState {
                    presentIcon(templateName: "arrow-down-24",
                                sizeInsideCircle: 15,
                                isInsideProgress: false)
                }
            case .downloadFailed:
                if oldState != newState {
                    presentIcon(templateName: "retry-alt-24",
                                sizeInsideCircle: 18,
                                isInsideProgress: false)
                }
            case .downloadProgress(let progress):
                switch oldState {
                case .downloadProgress:
                    updateProgress(progress: progress)
                default:
                    presentProgress(progress: progress)
                    presentIcon(templateName: "stop-20",
                                sizeInsideCircle: 10,
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
                                 isInsideProgress: Bool) {
            if !isInsideProgress {
                reset()
            }

            let iconSize: CGFloat
            let tintColor: UIColor
            switch style {
            case .withCircle:
                tintColor = .ows_white
                owsAssertDebug(sizeInsideCircle < diameter)
                iconSize = sizeInsideCircle
            case .withoutCircle:
                tintColor = Theme.primaryTextColor
                let fractionalSize: CGFloat = isInsideProgress ? 0.45 : 1.0
                iconSize = diameter * fractionalSize
            }
            imageView.setTemplateImageName(templateName, tintColor: tintColor)
            addSubview(imageView)
            layoutConstraints.append(contentsOf: imageView.autoSetDimensions(to: .square(iconSize)))
            layoutConstraints.append(contentsOf: imageView.autoCenterInSuperview())
        }

        private func presentProgress(progress: CGFloat) {
            reset()

            let animationName: String
            switch style {
            case .withCircle:
                animationName = "determinate_spinner"
            case .withoutCircle:
                animationName = (isIncoming && !isDarkThemeEnabled
                                    ? "determinate_spinner_blue"
                                    : "determinate_spinner")
            }
            let animationView = ensureAnimationView(progressView, animationName: animationName)
            progressView = animationView
            animationView.backgroundBehavior = .pause
            animationView.loopMode = .playOnce
            animationView.contentMode = .scaleAspectFit
            // We DO NOT play this animation; we "scrub" it to reflect
            // attachment upload/download progress.
            updateProgress(progress: progress)
            addSubview(animationView)
            layoutConstraints.append(contentsOf: animationView.autoPinEdgesToSuperviewEdges())
        }

        private func presentUnknownProgress() {
            reset()

            let animationName: String
            switch style {
            case .withCircle:
                animationName = "indeterminate_spinner"
            case .withoutCircle:
                animationName = (isIncoming && !isDarkThemeEnabled
                                    ? "indeterminate_spinner_blue"
                                    : "indeterminate_spinner")
            }
            let animationView = ensureAnimationView(unknownProgressView, animationName: animationName)
            unknownProgressView = animationView
            animationView.backgroundBehavior = .pauseAndRestore
            animationView.loopMode = .loop
            animationView.contentMode = .scaleAspectFit
            animationView.play()

            addSubview(animationView)
            layoutConstraints.append(contentsOf: animationView.autoPinEdgesToSuperviewEdges())
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

        private func reset() {
            removeAllSubviews()
            NSLayoutConstraint.deactivate(layoutConstraints)
            layoutConstraints.removeAll()
            progressView?.stop()
            unknownProgressView?.stop()
        }
    }

    private func createViews() {
        let innerContentView = self.stateView
        innerContentView.autoSetDimensions(to: .square(Self.innerDiameter(style: style)))

        let outerContentView: UIView
        switch style {
        case .withCircle:
            let circleView = OWSLayerView.circleView()
            circleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.7)
            circleView.autoSetDimensions(to: .square(Self.outerDiameter(style: style)))
            circleView.addSubview(innerContentView)
            innerContentView.autoCenterInSuperview()
            outerContentView = circleView
        case .withoutCircle:
            outerContentView = innerContentView
        }

        addSubview(outerContentView)
        outerContentView.autoPinEdgesToSuperviewEdges()
        outerContentView.setContentHuggingHigh()
        outerContentView.setCompressionResistanceHigh()
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
        if progress == CGFloat.nan {
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
        @unknown default:
            owsFailDebug("Invalid value.")
            stateView.state = .uploadUnknownProgress
            return
        }

        if progress.floatValue == Float.nan {
            owsFailDebug("Progress is nan.")
            stateView.state = .uploadUnknownProgress
        } else if progress.floatValue > 0 {
            stateView.state = .uploadProgress(progress: CGFloat(progress.floatValue))
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
}
