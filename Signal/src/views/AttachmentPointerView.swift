//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class AttachmentPointerView: UIView {

    let TAG = "[AttachmentPointerView]"

    let progressView = OWSProgressView()
    let nameLabel = UILabel()
    let statusLabel = UILabel()
    let isIncoming: Bool
    let filename: String
    let attachmentPointer: TSAttachmentPointer
    let genericFilename = NSLocalizedString("ATTACHMENT_DEFAULT_FILENAME", comment: "Generic filename for an attachment with no known name")

    var progress: CGFloat = 0 {
        didSet {
            self.progressView.progress = progress
        }
    }

    required init(attachmentPointer: TSAttachmentPointer, isIncoming: Bool) {
        self.isIncoming = isIncoming
        self.attachmentPointer = attachmentPointer

        let attachmentPointerFilename = attachmentPointer.sourceFilename
        if let filename = attachmentPointerFilename, !filename.isEmpty {
          self.filename = filename
        } else {
            self.filename = genericFilename
        }

        super.init(frame: CGRect.zero)

        createSubviews()
        updateViews()
    }

    @available(*, unavailable)
    override init(frame: CGRect) {
        assertionFailure()
        // This initializer should never be called, but we assign some bogus values to keep the compiler happy.
        self.filename = genericFilename
        self.isIncoming = false
        self.attachmentPointer = TSAttachmentPointer()
        super.init(frame: frame)
        self.createSubviews()
        self.updateViews()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        assertionFailure()
        // This initializer should never be called, but we assign some bogus values to keep the compiler happy.
        self.filename = genericFilename
        self.isIncoming = false
        self.attachmentPointer = TSAttachmentPointer()
        super.init(coder: aDecoder)
        self.createSubviews()
        self.updateViews()
    }

    func createSubviews() {
        self.addSubview(nameLabel)
        // truncate middle to be sure we include file extension
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.textAlignment = .center

        nameLabel.textColor = self.textColor
        nameLabel.font = UIFont.ows_dynamicTypeBody()

        nameLabel.autoPinWidthToSuperview()
        nameLabel.autoPinEdge(toSuperviewEdge: .top)

        self.addSubview(progressView)
        progressView.autoPinWidthToSuperview()
        progressView.autoPinEdge(.top, to: .bottom, of: nameLabel, withOffset: 6)
        progressView.autoSetDimension(.height, toSize: 8)

        self.addSubview(statusLabel)
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true

        statusLabel.textColor = self.textColor
        statusLabel.font = UIFont.ows_footnote()

        statusLabel.autoPinWidthToSuperview()
        statusLabel.autoPinEdge(.top, to: .bottom, of: progressView, withOffset: 4)
        statusLabel.autoPinEdge(toSuperviewEdge: .bottom)
    }

    func emojiForContentType(_ contentType: String) -> String {
        if MIMETypeUtil.isImage(contentType) {
            return "📷"
        } else if MIMETypeUtil.isVideo(contentType) {
            return "📽"
        } else if MIMETypeUtil.isAudio(contentType) {
            return "📻"
        } else if MIMETypeUtil.isAnimated(contentType) {
            return "🎡"
        } else {
            // generic file
            return "📁"
        }
    }

    func updateViews() {
        let emoji = self.emojiForContentType(self.attachmentPointer.contentType)
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
        } else {
            progressView.isHidden = true
        }
    }

    var textColor: UIColor {
        return self.isIncoming ? UIColor.darkText : UIColor.white
    }
}
