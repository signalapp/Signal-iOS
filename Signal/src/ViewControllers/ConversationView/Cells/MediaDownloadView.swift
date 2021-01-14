//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MediaDownloadView: UIView {

    private let attachmentId: String
    private let progressView: CircularProgressView

    @objc
    public var progressTrackColor: UIColor {
        get {
            return progressView.trackColor
        }
        set {
            progressView.trackColor = newValue
        }
    }
    @objc
    public var progressColor: UIColor {
        get {
            return progressView.progressColor
        }
        set {
            progressView.progressColor = newValue
        }
    }

    @objc
    public required init(attachmentId: String, radius: CGFloat, withCircle: Bool = false) {
        self.attachmentId = attachmentId
        progressView = CircularProgressView(thickness: 0.1)

        super.init(frame: .zero)

        self.isUserInteractionEnabled = false

        if withCircle {
            let circleView = OWSLayerView.circleView(size: radius * 2)
            circleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.7)
            addSubview(circleView)
            circleView.autoCenterInSuperview()

            circleView.addSubview(progressView)
            progressView.autoSetDimensions(to: CGSize.square(radius * 2 * 32 / 44))
            progressView.autoCenterInSuperview()
        } else {
            addSubview(progressView)
            progressView.autoSetDimensions(to: CGSize.square(radius * 2))
            progressView.autoCenterInSuperview()
        }

        NotificationCenter.default.addObserver(forName: OWSAttachmentDownloads.attachmentDownloadProgressNotification,
                                               object: nil,
                                               queue: nil) { [weak self] notification in
            guard let strongSelf = self else { return }
                                                guard let notificationAttachmentId = notification.userInfo?[OWSAttachmentDownloads.attachmentDownloadAttachmentIDKey] as? String else {
                return
            }
            guard notificationAttachmentId == strongSelf.attachmentId else {
                return
            }
            strongSelf.updateProgress()
        }
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    internal func updateProgress() {
        AssertIsOnMainThread()

        guard let progress = attachmentDownloads.downloadProgress(forAttachmentId: attachmentId) else {
            Logger.warn("No progress for attachment.")

            progressView.progress = 0
            return
        }
        progressView.progress = CGFloat(progress.floatValue)
    }
}
