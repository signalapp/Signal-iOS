//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI
import UIKit

// A view for presenting attachment upload/download/failure/pending state.
class CVAttachmentProgressView: ManualLayoutView {

    enum Direction {
        case upload(attachmentStream: AttachmentStream)
        case download(attachmentPointer: AttachmentPointer, downloadState: AttachmentDownloadState)

        var attachmentId: Attachment.IDType {
            switch self {
            case .upload(let attachmentStream):
                return attachmentStream.id
            case .download(let attachmentPointer, _):
                return attachmentPointer.id
            }
        }
    }

    struct ColorConfiguration {
        enum BackgroundStyle {
            case solidColor(UIColor)
            case blur(UIBlurEffect)
        }

        let foregroundColor: UIColor
        let backgroundStyle: BackgroundStyle

        private init(foregroundColor: UIColor, backgroundStyle: BackgroundStyle) {
            self.foregroundColor = foregroundColor
            self.backgroundStyle = backgroundStyle
        }

        init(conversationStyle: ConversationStyle, isIncoming: Bool) {
            foregroundColor = conversationStyle.bubbleTextColor(isIncoming: isIncoming)
            let backgroundColor = switch (conversationStyle.hasWallpaper, isIncoming) {
            case (true, true): UIColor.Signal.MaterialBase.button
            case (_, true): UIColor.Signal.LightBase.button
            case (_, false): UIColor.Signal.ColorBase.button
            }
            backgroundStyle = .solidColor(backgroundColor)
        }

        /// Creates a configuration with fixed colors to be displayed on top of media thumbnail.
        static func forMediaOverlay() -> ColorConfiguration {
            ColorConfiguration(
                foregroundColor: .Signal.label,
                backgroundStyle: .blur(.init(style: .systemThinMaterial)),
            )
        }
    }

    private let direction: Direction
    private let diameter: CGFloat

    private let stateView: StateView

    private var attachmentId: Attachment.IDType { direction.attachmentId }

    init(
        direction: Direction,
        diameter: CGFloat = 44,
        colorConfiguration: ColorConfiguration,
        mediaCache: CVMediaCache,
    ) {
        self.direction = direction
        self.diameter = diameter
        self.stateView = StateView(
            diameter: diameter,
            direction: direction,
            mediaCache: mediaCache,
        )

        super.init(name: "CVAttachmentProgressView")

        stateView.tintColor = colorConfiguration.foregroundColor

        let circleView = ManualLayoutView.circleView(name: "circleView")
        switch colorConfiguration.backgroundStyle {
        case .solidColor(let backgroundColor):
            circleView.backgroundColor = backgroundColor
        case .blur(let blurEffect):
            circleView.clipsToBounds = true
            let blurView = UIVisualEffectView(effect: blurEffect)
            circleView.addSubviewToFillSuperviewEdges(blurView)
        }
        circleView.addSubviewToCenterOnSuperview(stateView, size: .square(diameter))
        addSubviewToFillSuperviewEdges(circleView)

        configureState()
    }

    private class StateView: ManualLayoutView {
        enum State: Equatable {
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

        private let diameter: CGFloat
        private let direction: Direction
        private lazy var imageView = CVImageView()
        private var unknownProgressView: LottieAnimationView?
        private var progressView: LottieAnimationView?
        private let mediaCache: CVMediaCache

        var state: State = .none {
            didSet {
                if oldValue != state {
                    applyState(oldState: oldValue, newState: state)
                }
            }
        }

        init(
            diameter: CGFloat,
            direction: Direction,
            mediaCache: CVMediaCache,
        ) {
            self.diameter = diameter
            self.direction = direction
            self.mediaCache = mediaCache

            super.init(name: "CVAttachmentProgressView.StateView")

            applyState(oldState: .none, newState: .none)
        }

        private func applyState(oldState: State, newState: State) {
            switch newState {
            case .none:
                reset()

            case .tapToDownload:
                presentIcon(templateName: Theme.iconName(.arrowDown), isInsideProgress: false)

            case .downloadFailed:
                presentIcon(templateName: Theme.iconName(.refresh), isInsideProgress: false)

            case .downloadProgress(let progress):
                switch oldState {
                case .downloadProgress:
                    updateProgress(progress: progress)
                default:
                    presentProgress(progress: progress)
                    presentIcon(templateName: Theme.iconName(.buttonX), isInsideProgress: true)
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
                presentIcon(templateName: Theme.iconName(.buttonX), isInsideProgress: true)

            case .uploadUnknownProgress:
                presentUnknownProgress()
            }
        }

        private func presentIcon(
            templateName: String,
            isInsideProgress: Bool,
        ) {
            if !isInsideProgress {
                reset()
            }

            imageView.setTemplateImageName(templateName, tintColor: tintColor)
            addSubviewToCenterOnSuperview(imageView, size: .square(floor(0.44 * diameter)))
        }

        private func presentProgress(progress: CGFloat) {
            reset()

            let animationName: String
            if diameter <= 44 {
                animationName = "determinate_spinner_44"
            } else {
                animationName = "determinate_spinner_56"
            }
            let animationView = ensureAnimationView(progressView, animationName: animationName)
            owsAssertDebug(animationView.animation != nil)
            progressView = animationView
            animationView.backgroundBehavior = .pause
            animationView.loopMode = .playOnce
            animationView.contentMode = .scaleAspectFit
            animationView.setValueProvider(
                ColorValueProvider(tintColor.lottieColorValue),
                keypath: AnimationKeypath(keypath: "**.Stroke 1.Color"),
            )
            // We DO NOT play this animation; we "scrub" it to reflect
            // attachment upload/download progress.
            updateProgress(progress: progress)
            addSubviewToFillSuperviewEdges(animationView)
        }

        private func presentUnknownProgress() {
            reset()

            let animationName: String
            if diameter <= 44 {
                animationName = "indeterminate_spinner_44"
            } else {
                animationName = "indeterminate_spinner_56"
            }
            let animationView = ensureAnimationView(unknownProgressView, animationName: animationName)
            owsAssertDebug(animationView.animation != nil)
            unknownProgressView = animationView
            animationView.backgroundBehavior = .pauseAndRestore
            animationView.loopMode = .loop
            animationView.contentMode = .scaleAspectFit
            animationView.setValueProvider(
                ColorValueProvider(tintColor.lottieColorValue),
                keypath: AnimationKeypath(keypath: "**.Stroke 1.Color"),
            )
            animationView.play()

            addSubviewToFillSuperviewEdges(animationView)
        }

        private func ensureAnimationView(
            _ animationView: LottieAnimationView?,
            animationName: String,
        ) -> LottieAnimationView {
            if let animationView {
                return animationView
            }
            return mediaCache.buildLottieAnimationView(name: animationName)
        }

        private func updateProgress(progress: CGFloat) {
            guard let progressView else {
                owsFailDebug("Missing progressView.")
                return
            }
            guard let animation = progressView.animation else {
                owsFailDebug("Missing animation.")
                return
            }

            // We DO NOT play this animation; we "scrub" it to reflect
            // attachment upload/download progress.
            progressView.currentFrame = progress.lerp(
                animation.startFrame,
                animation.endFrame,
            )
        }

        override func reset() {
            super.reset()

            progressView?.stop()
            unknownProgressView?.stop()
            imageView.image = nil
        }
    }

    var layoutSize: CGSize {
        .square(diameter)
    }

    private func configureState() {
        switch direction {
        case .upload(let attachmentStream):
            stateView.state = .uploadUnknownProgress

            updateUploadProgress(attachmentStream: attachmentStream)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(processUploadNotification(notification:)),
                name: Upload.Constants.attachmentUploadProgressNotification,
                object: nil,
            )

        case .download(_, let downloadState):
            switch downloadState {
            case .failed:
                stateView.state = .downloadFailed
            case .none:
                stateView.state = .tapToDownload
            case .enqueuedOrDownloading:
                updateDownloadProgress(nil)

                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(processDownloadNotification(notification:)),
                    name: AttachmentDownloads.attachmentDownloadProgressNotification,
                    object: nil,
                )
            }
        }
    }

    @objc
    private func processDownloadNotification(notification: Notification) {
        guard
            let attachmentId = notification.userInfo?[AttachmentDownloads.attachmentDownloadAttachmentIDKey] as? Attachment.IDType
        else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard attachmentId == self.attachmentId else {
            return
        }
        let progress = notification.userInfo?[AttachmentDownloads.attachmentDownloadProgressKey] as? CGFloat
        if progress == nil {
            Logger.warn("No progress for attachment progress notification.")
        }
        updateDownloadProgress(progress)
    }

    private func updateDownloadProgress(_ progress: CGFloat?) {
        AssertIsOnMainThread()

        guard let progress else {
            stateView.state = .downloadUnknownProgress
            return
        }

        updateState(downloadProgress: progress)
    }

    private func updateState(downloadProgress progress: CGFloat?) {
        guard let progress else {
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
        guard let notificationAttachmentId = notification.userInfo?[Upload.Constants.uploadAttachmentIDKey] as? Attachment.IDType else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard notificationAttachmentId == attachmentId else {
            return
        }
        guard let progress = notification.userInfo?[Upload.Constants.uploadProgressKey] as? NSNumber else {
            owsFailDebug("Missing progress.")
            stateView.state = .uploadUnknownProgress
            return
        }

        switch direction {
        case .upload(let attachmentStream):
            guard !attachmentStream.attachment.isUploadedToTransitTier else {
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

    private func updateUploadProgress(attachmentStream: AttachmentStream) {
        AssertIsOnMainThread()

        if attachmentStream.attachment.isUploadedToTransitTier {
            stateView.state = .uploadProgress(progress: 1)
        } else {
            stateView.state = .uploadUnknownProgress
        }
    }

    enum ProgressType {
        case none
        case uploading(attachmentStream: AttachmentStream)
        case pendingDownload(attachmentPointer: AttachmentPointer)
        case downloading(attachmentPointer: AttachmentPointer, downloadState: AttachmentDownloadState)
        case unknown
    }

    static func progressType(
        forAttachment attachment: CVAttachment,
        interaction: TSInteraction,
    ) -> ProgressType {

        switch attachment {
        case .backupThumbnail:
            // TODO: [Backups]: Update download state based on the media tier attachment state
            return .none
        case .stream(let attachmentStream):
            if let outgoingMessage = interaction as? TSOutgoingMessage {
                let hasSendFailed = outgoingMessage.messageState == .failed
                let wasNotCreatedLocally = outgoingMessage.wasNotCreatedLocally
                guard
                    !attachmentStream.attachment.isUploadedToTransitTier,
                    !attachmentStream.attachment.hasMediaTierInfo,
                    !wasNotCreatedLocally,
                    !hasSendFailed
                else {
                    return .none
                }
                return .uploading(attachmentStream: attachmentStream.attachmentStream)
            } else if interaction is TSIncomingMessage {
                return .none
            } else {
                owsFailDebug("Unexpected interaction: \(type(of: interaction))")
                return .unknown
            }
        case .pointer(let attachmentPointer, let downloadState):
            switch downloadState {
            case .none:
                return .pendingDownload(attachmentPointer: attachmentPointer.attachmentPointer)
            case .failed, .enqueuedOrDownloading:
                return .downloading(
                    attachmentPointer: attachmentPointer.attachmentPointer,
                    downloadState: downloadState,
                )
            }
        case .undownloadable:
            return .none
        }
    }
}
