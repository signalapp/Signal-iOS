//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MediaDownloadView: UIView {

    // MARK: - Dependencies

    private var attachmentDownloads: OWSAttachmentDownloads {
        return SSKEnvironment.shared.attachmentDownloads
    }

    // MARK: -

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
    public required init(attachmentId: String, radius: CGFloat) {
        self.attachmentId = attachmentId
        progressView = CircularProgressView(thickness: 0.1)

        super.init(frame: .zero)

        addSubview(progressView)
        progressView.autoSetDimension(.width, toSize: radius * 2)
        progressView.autoSetDimension(.height, toSize: radius * 2)
        progressView.autoCenterInSuperview()

        NotificationCenter.default.addObserver(forName: NSNotification.Name.attachmentDownloadProgress, object: nil, queue: nil) { [weak self] notification in
            guard let strongSelf = self else { return }
            guard let notificationAttachmentId = notification.userInfo?[kAttachmentDownloadAttachmentIDKey] as? String else {
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
