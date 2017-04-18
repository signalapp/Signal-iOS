//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

/**
 * Represents a download-in-progress
 */
class DownloadingAttachmentAdapter: JSQMediaItem, OWSMessageEditing {

    let TAG = "[OWSDownloadingAttachment]"
    let isOutgoing: Bool
    let attachmentPointer: TSAttachmentPointer
    var cachedView: UIView?
    var progressView: OWSProgressView?

    required init(attachmentPointer: TSAttachmentPointer, maskAsOutgoing isOutgoing: Bool) {
        self.isOutgoing = isOutgoing
        self.attachmentPointer = attachmentPointer
        super.init(maskAsOutgoing: isOutgoing)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        assertionFailure("init(coder:) has not been implemented")
        self.isOutgoing = false
        self.attachmentPointer = TSAttachmentPointer()
        super.init(coder: aDecoder)
    }

    func canPerformAction(_ action: Selector) -> Bool {
        // No actions can be performed on a downloading attachment.
        return false
    }

    func performAction(_ action: Selector) {
        // Should not get here, as you can't perform any actions on a downloading attachment.
        Logger.error("\(TAG) unexpectedly trying to perform action: \(action) on downloading attachment.")
        assertionFailure()
    }

    override func mediaViewDisplaySize() -> CGSize {
        return CGSize(width: 200, height: 80)
    }

    override func mediaView() -> UIView? {
        guard self.cachedView == nil else {
            return self.cachedView
        }

        let frame = CGRect(origin: CGPoint.zero, size: self.mediaViewDisplaySize())
        let downloadingView = UIView(frame: frame)
        self.cachedView = downloadingView

        JSQMessagesMediaViewBubbleImageMasker.applyBubbleImageMask(toMediaView: downloadingView, isOutgoing:self.isOutgoing)

        downloadingView.backgroundColor = UIColor.jsq_messageBubbleLightGray()
        downloadingView.isUserInteractionEnabled = false

        let progressView = OWSProgressView()
        self.progressView = progressView

        downloadingView.addSubview(progressView)

        progressView.autoPinWidthToSuperview(withMargin: 20)
        progressView.autoPinEdge(toSuperviewEdge: .top, withInset: 24)

        let label = UILabel()
        downloadingView.addSubview(label)
        label.text = NSLocalizedString("ATTACHMENT_DOWNLOADING", comment: "Label text for an attachment that is currently being downloaded")
        label.textAlignment = .center
        label.textColor = UIColor.darkText
        label.adjustsFontSizeToFitWidth = true
        label.font = UIFont.ows_infoMessage()

        label.autoPinWidthToSuperview(withMargin: 20)
        label.autoPinEdge(.top, to: .bottom, of: progressView, withOffset: 4)

        NotificationCenter.default.addObserver(self, selector: #selector(attachmentDownloadProgress), name: NSNotification.Name.attachmentDownloadProgress, object: nil)

        return cachedView
    }

    func attachmentDownloadProgress(_ notification: NSNotification) {
        guard let progressView = self.progressView else {
            Logger.error("\(TAG) progress view was unexpectedly nil for notification: \(notification)")
            assertionFailure()
            return
        }

        guard let userInfo = notification.userInfo else {
            Logger.error("\(TAG) user info was unexpectedly nil for notification: \(notification)")
            assertionFailure()
            return
        }

        guard let progress = userInfo[kAttachmentDownloadProgressKey] as? CGFloat else {
            Logger.error("\(TAG) missing progress measure for notification user info: \(userInfo)")
            assertionFailure()
            return
        }

        guard let attachmentId = userInfo[kAttachmentDownloadAttachmentIDKey] as? String else {
            Logger.error("\(TAG) missing attachmentId for notification user info: \(userInfo)")
            assertionFailure()
            return
        }

        if (self.attachmentPointer.uniqueId == attachmentId) {
            progressView.progress = progress
        }
    }
}
