//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

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
            return ColorConfiguration(
                foregroundColor: .Signal.label,
                backgroundStyle: .blur(.init(style: .systemThinMaterial)),
            )
        }
    }

    enum State: Equatable {
        case none

        case tapToDownload
        case unknownProgress
        case progress(progress: Float)

        var debugDescription: String {
            switch self {
            case .none:
                "none"
            case .tapToDownload:
                "tapToDownload"
            case .unknownProgress:
                "unknownProgress"
            case .progress(let progress):
                "progress: \(progress)"
            }
        }
    }

    private let direction: Direction

    private var _state: State = .none

    var state: State {
        get {
            _state
        }
        set {
            applyState(newValue, animated: false)
        }
    }

    private var attachmentId: Attachment.IDType { direction.attachmentId }

    init(
        direction: Direction,
        colorConfiguration: ColorConfiguration,
    ) {
        self.direction = direction

        super.init(name: "CVAttachmentProgressView")

        tintColor = colorConfiguration.foregroundColor
        layoutMargins = .init(margin: 4)

        // Circular background.
        let circleView = ManualLayoutView.circleView(name: "circleView")
        switch colorConfiguration.backgroundStyle {
        case .solidColor(let backgroundColor):
            circleView.backgroundColor = backgroundColor
        case .blur(let blurEffect):
            circleView.clipsToBounds = true
            let blurView = UIVisualEffectView(effect: blurEffect)
            circleView.addSubviewToFillSuperviewEdges(blurView)
        }
        addSubviewToFillSuperviewEdges(circleView)

        addSubviewToFillSuperviewMargins(contentView)

        addLayoutBlock { view in
            guard let view = view as? CVAttachmentProgressView else { return }
            DispatchQueue.main.async {
                view.loadInitialStateIfNeeded()
            }
        }
    }

    // MARK: State

    private let contentView = ManualLayoutViewWithLayer(name: "contentView")
    private var progressView: CircularProgressView?
    private var iconImageView: CVImageView?

    // Set initial state and update UI accordingly without animations.
    private func loadInitialStateIfNeeded() {
        guard state == .none, window != nil, contentView.bounds.size.isNonEmpty else { return }

        let animateStateChange = window != nil

        switch direction {
        case .upload:
            applyState(.unknownProgress, animated: animateStateChange)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(processUploadNotification(notification:)),
                name: Upload.Constants.attachmentUploadProgressNotification,
                object: nil,
            )

        case .download(_, let downloadState):
            switch downloadState {
            case .none, .failed:
                applyState(.tapToDownload, animated: animateStateChange)
            case .enqueuedOrDownloading:
                applyState(.unknownProgress, animated: animateStateChange)

                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(processDownloadNotification(notification:)),
                    name: AttachmentDownloads.attachmentDownloadProgressNotification,
                    object: nil,
                )
            }
        }
    }

    private func applyState(_ state: State, animated: Bool = false) {
        let oldState = _state

        guard state != oldState else { return }

        _state = state

        switch state {
        case .none:
            hideProgressView()

        case .tapToDownload:
            hideProgressView()
            presentIcon(Theme.iconImage(.arrowDown))

        case .progress(let progress):
            switch oldState {
            case .progress, .unknownProgress:
                updateProgressView(progress: progress, animated: animated)
            default:
                presentProgressView(progress: progress, animated: animated)
                if case .download = direction {
                    presentIcon(UIImage(named: "stop-20")!)
                } else {
                    hideIcon()
                }
            }

        case .unknownProgress:
            presentIndeterminateProgressView(animated: animated)
            if case .download = direction {
                presentIcon(UIImage(named: "stop-20")!)
            } else {
                hideIcon()
            }
        }
    }

    private func presentIcon(_ image: UIImage) {
        let imageView = ensureIconImageView()
        imageView.image = image
    }

    private func hideIcon() {
        iconImageView?.image = nil
    }

    private func ensureIconImageView() -> CVImageView {
        if let iconImageView {
            return iconImageView
        }
        let imageView = CVImageView(frame: contentView.bounds)
        imageView.contentMode = .center
        contentView.addSubviewToFillSuperviewEdges(imageView)
        self.iconImageView = imageView
        return imageView
    }

    private func presentIndeterminateProgressView(animated: Bool) {
        let progressView = ensureProgressView()

        guard animated else {
            progressView.isHidden = false
            progressView.startAnimating()
            return
        }

        UIView.performWithoutAnimation {
            progressView.isHidden = false
            contentView.transform = .scale(0.8)
        }

        let animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 1, springResponse: 0.25)
        animator.addAnimations {
            self.contentView.transform = .identity
        }
        animator.addCompletion { [weak self] animationPosition in
            guard let self, self.state == .unknownProgress else { return }
            self.progressView?.startAnimating()
        }
        animator.startAnimation()
    }

    private func presentProgressView(progress: Float, animated: Bool) {
        let progressView = ensureProgressView()

        guard animated else {
            progressView.isHidden = false
            progressView.progress = progress
            return
        }
        UIView.performWithoutAnimation {
            progressView.isHidden = false
            progressView.progress = progress
            self.contentView.transform = .scale(0.8)
        }

        let animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 1, springResponse: 0.25)
        animator.addAnimations {
            self.contentView.transform = .identity
        }
        animator.startAnimation()
    }

    private func updateProgressView(progress: Float, animated: Bool) {
        guard let progressView else {
            owsFailDebug("Missing progressView.")
            return
        }
        progressView.setProgress(progress, animated: animated)
    }

    // Create CircularProgressView, add it to view hierarchy and make it visible.
    private func ensureProgressView() -> CircularProgressView {
        if let progressView {
            progressView.isHidden = false
            return progressView
        }
        let progressView = CircularProgressView(frame: contentView.bounds)
        contentView.addSubviewToFillSuperviewEdges(progressView)
        self.progressView = progressView
        return progressView
    }

    private func hideProgressView() {
        progressView?.stopAnimating()
        progressView?.isHidden = true
    }

    @objc
    private func processDownloadNotification(notification: Notification) {
        AssertIsOnMainThread()

        guard
            let attachmentId = notification.userInfo?[AttachmentDownloads.attachmentDownloadAttachmentIDKey] as? Attachment.IDType
        else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard attachmentId == self.attachmentId else {
            return
        }
        guard let progress = notification.userInfo?[AttachmentDownloads.attachmentDownloadProgressKey] as? Float else {
            owsFailDebug("No progress in attachment download progress notification.")
            state = .unknownProgress
            return
        }
        guard progress.isNaN == false, progress >= 0 else {
            owsFailDebug("Invalid download progress value. [\(progress)]")
            state = .unknownProgress
            return
        }
        applyState(.progress(progress: progress), animated: window != nil)
    }

    @objc
    private func processUploadNotification(notification: Notification) {
        AssertIsOnMainThread()

        guard let notificationAttachmentId = notification.userInfo?[Upload.Constants.uploadAttachmentIDKey] as? Attachment.IDType else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard notificationAttachmentId == attachmentId else {
            return
        }
        guard let progress = notification.userInfo?[Upload.Constants.uploadProgressKey] as? Float else {
            owsFailDebug("No progress in attachment upload progress notification.")
            state = .unknownProgress
            return
        }
        guard progress.isNaN == false, progress >= 0 else {
            owsFailDebug("Invalid upload progress value. [\(progress)]")
            state = .unknownProgress
            return
        }

        applyState(.progress(progress: progress), animated: window != nil)
    }

    enum ProgressType {
        case none
        case uploading(attachmentStream: AttachmentStream)
        case skipped(attachmentPointer: AttachmentPointer)
        case downloading(attachmentPointer: AttachmentPointer, downloadState: AttachmentDownloadState)
    }

    static func progressType(cvAttachment: CVAttachment) -> ProgressType {
        switch cvAttachment {
        case .backupThumbnail:
            // TODO: [Backups]: Update download state based on the media tier attachment state
            return .none
        case .stream(let referencedAttachmentStream, let isUploading):
            if isUploading {
                return .uploading(attachmentStream: referencedAttachmentStream.attachmentStream)
            } else {
                return .none
            }
        case .pointer(let attachmentPointer, let downloadState):
            switch downloadState {
            case .none:
                return .skipped(attachmentPointer: attachmentPointer.attachmentPointer)
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
