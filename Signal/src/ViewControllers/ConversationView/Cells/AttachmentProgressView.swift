//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

// A view for presenting attachment upload/download/failure/pending state.
@objc
public class AttachmentProgressView: UIView {

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

    private var attachmentId: String { direction.attachmentId }

    private let stateView: StateView

    public required init(direction: Direction, style: Style) {
        self.direction = direction
        self.style = style
        self.stateView = StateView(diameter: Self.innerDiameter(style: style), style: style)

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
    }

    private class StateView: UIView {
        private let diameter: CGFloat
        private let style: Style
        private lazy var imageView = UIImageView()
        private lazy var progressView = CircularProgressView(thickness: 0.1)

        private var layoutConstraints = [NSLayoutConstraint]()

        var state: State = .none {
            didSet {
                applyState(oldState: oldValue, newState: state)
            }
        }

        required init(diameter: CGFloat, style: Style) {
            self.diameter = diameter
            self.style = style

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
                    presentIcon(templateName: "arrow-down-24", fractionalSize: 0.5)
                }
            case .downloadFailed:
                if oldState != newState {
                    presentIcon(templateName: "retry-alt-24", fractionalSize: 0.5)
                }
            case .downloadProgress(let progress):
                switch oldState {
                case .downloadProgress:
                    updateProgress(progress: progress)
                default:
                    presentProgress(progress: progress)
                    presentIcon(templateName: "pause-filled-24", fractionalSize: 0.5, isPauseIcon: true)
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
                presentIcon(templateName: "pause-filled-24", fractionalSize: 0.5, isPauseIcon: true)
            case .uploadUnknownProgress:
                presentUnknownProgress()
            }
        }

        private func presentIcon(templateName: String,
                                 fractionalSize: CGFloat,
                                 isPauseIcon: Bool = false) {
            if !isPauseIcon {
                reset()
            }

            let iconSize: CGFloat
            let tintColor: UIColor
            switch style {
            case .withCircle:
                tintColor = .ows_white
                iconSize = diameter * fractionalSize
            case .withoutCircle:
                tintColor = Theme.primaryTextColor
                if isPauseIcon {
                    iconSize = diameter * fractionalSize
                } else {
                    iconSize = diameter
                }
            }
            imageView.setTemplateImageName(templateName, tintColor: tintColor)
            addSubview(imageView)
            layoutConstraints.append(contentsOf: imageView.autoSetDimensions(to: .square(iconSize)))
        }

        private func presentProgress(progress: CGFloat) {
            reset()

            progressView.progress = progress
            switch style {
            case .withCircle:
                break
            case .withoutCircle:
                progressView.progressColor = Theme.primaryTextColor
            }
            addSubview(progressView)
            layoutConstraints.append(contentsOf: progressView.autoPinEdgesToSuperviewEdges())
        }

        private func updateProgress(progress: CGFloat) {
            progressView.progress = progress
        }

        private func reset() {
            removeAllSubviews()
            NSLayoutConstraint.deactivate(layoutConstraints)
            layoutConstraints.removeAll()
            unknownProgressAnimation?.stop()
        }

        private var unknownProgressAnimation: AnimationView?

        private func presentUnknownProgress() {
            reset()

            let animationView: AnimationView
            if let unknownProgressAnimation = unknownProgressAnimation {
                animationView = unknownProgressAnimation
            } else {
                animationView = AnimationView(name: "pinCreationInProgress")
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.loopMode = .loop
                animationView.contentMode = .scaleAspectFit
            }
            animationView.play()

            addSubview(animationView)
            layoutConstraints.append(contentsOf: animationView.autoPinEdgesToSuperviewEdges())
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
        case .upload:
            stateView.state = .uploadUnknownProgress

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
            return
        }
        if progress == CGFloat.nan {
            owsFailDebug("Progress is nan.")
            stateView.state = .downloadUnknownProgress
        } else {
            stateView.state = .downloadProgress(progress: CGFloat(progress))
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
            return
        }

        if progress.floatValue == Float.nan {
            owsFailDebug("Progress is nan.")
            stateView.state = .uploadUnknownProgress
        } else {
            stateView.state = .uploadProgress(progress: CGFloat(progress.floatValue))
        }
    }
}
