//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class AttachmentPointerView: UIStackView {

    let isIncoming: Bool
    let attachmentPointer: TSAttachmentPointer
    let conversationStyle: ConversationStyle

    let progressView = OWSProgressView()
    let nameLabel = UILabel()
    let statusLabel = UILabel()
    let filename: String
    let genericFilename = NSLocalizedString("ATTACHMENT_DEFAULT_FILENAME", comment: "Generic filename for an attachment with no known name")

    var progress: CGFloat = 0 {
        didSet {
            self.progressView.progress = progress
        }
    }

    @objc
    required init(attachmentPointer: TSAttachmentPointer, isIncoming: Bool, conversationStyle: ConversationStyle) {
        self.attachmentPointer = attachmentPointer
        self.isIncoming = isIncoming
        self.conversationStyle = conversationStyle

        let attachmentPointerFilename = attachmentPointer.sourceFilename
        if let filename = attachmentPointerFilename, !filename.isEmpty {
          self.filename = filename
        } else {
            self.filename = genericFilename
        }

        super.init(frame: CGRect.zero)

        createSubviews()
        updateViews()

        if attachmentPointer.state == .downloading {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(attachmentDownloadProgress(_:)),
                                                   name: NSNotification.Name.attachmentDownloadProgress,
                                                   object: nil)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc internal func attachmentDownloadProgress(_ notification: Notification) {
        guard let attachmentId = attachmentPointer.uniqueId else {
            owsFailDebug("Missing attachment id.")
            return
        }
        guard let progress = (notification as NSNotification).userInfo?[kAttachmentDownloadProgressKey] as? NSNumber else {
            owsFailDebug("Attachment download notification missing progress.")
            return
        }
        guard let notificationAttachmentId = (notification as NSNotification).userInfo?[kAttachmentDownloadAttachmentIDKey] as? String else {
            owsFailDebug("Attachment download notification missing attachment id.")
            return
        }
        guard notificationAttachmentId == attachmentId else {
            return
        }
        self.progress = CGFloat(progress.floatValue)
    }

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private static var vSpacing: CGFloat = 5
    private class func nameFont() -> UIFont { return UIFont.ows_dynamicTypeBody }
    private class func statusFont() -> UIFont { return UIFont.ows_dynamicTypeCaption1 }
    private static var progressWidth: CGFloat = 80
    private static var progressHeight: CGFloat = 6

    func createSubviews() {
        progressView.autoSetDimension(.width, toSize: AttachmentPointerView.progressWidth)
        progressView.autoSetDimension(.height, toSize: AttachmentPointerView.progressHeight)

        // truncate middle to be sure we include file extension
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.textAlignment = .center
        nameLabel.textColor = self.textColor
        nameLabel.font = AttachmentPointerView.nameFont()

        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.numberOfLines = 2
        statusLabel.textColor = self.textColor
        statusLabel.font = AttachmentPointerView.statusFont()

        self.axis = .vertical
        self.spacing = AttachmentPointerView.vSpacing
        addArrangedSubview(nameLabel)
        addArrangedSubview(progressView)
        addArrangedSubview(statusLabel)
    }

    func updateViews() {
        let emoji = TSAttachment.emoji(forMimeType: self.attachmentPointer.contentType)
        nameLabel.text = "\(emoji) \(self.filename)"

        statusLabel.text = {
            switch self.attachmentPointer.state {
            case .enqueued:
                return NSLocalizedString("ATTACHMENT_DOWNLOADING_STATUS_QUEUED", comment: "Status label when an attachment is enqueued, but hasn't yet started downloading")
            case .downloading:
                return NSLocalizedString("ATTACHMENT_DOWNLOADING_STATUS_IN_PROGRESS", comment: "Status label when an attachment is currently downloading")
            case .failed:
                return NSLocalizedString("ATTACHMENT_DOWNLOADING_STATUS_FAILED", comment: "Status label when an attachment download has failed.")
            }
        }()

        if attachmentPointer.state == .downloading {
            progressView.isHidden = false
            progressView.autoSetDimension(.height, toSize: 8)
        } else {
            progressView.isHidden = true
            progressView.autoSetDimension(.height, toSize: 0)
        }
    }

    var textColor: UIColor {
        return conversationStyle.bubbleTextColor(isIncoming: isIncoming)
    }

    @objc
    public class func measureHeight() -> CGFloat {
        return ceil(nameFont().lineHeight +
            statusFont().lineHeight +
            progressHeight +
            vSpacing * 2)
    }
}
