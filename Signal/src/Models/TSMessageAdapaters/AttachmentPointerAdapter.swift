//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

/**
 * Represents a download-in-progress
 */
class AttachmentPointerAdapter: JSQMediaItem, OWSMessageEditing {

    let TAG = "[AttachmentPointerAdapter]"
    let isIncoming: Bool
    let attachmentPointer: TSAttachmentPointer
    var cachedView: UIView?
    var attachmentPointerView: AttachmentPointerView?

    required init(attachmentPointer: TSAttachmentPointer, isIncoming: Bool) {
        self.isIncoming = isIncoming
        self.attachmentPointer = attachmentPointer
        super.init(maskAsOutgoing: !isIncoming)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        assertionFailure("init(coder:) has not been implemented")
        self.isIncoming = true
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

    // MARK: JSQ Overrides

    override func mediaHash() -> UInt {
        // In objc, `hash` returns NSUInteger, but in Swift it return an Int.
        assert(self.attachmentPointer.uniqueId != nil)
        return UInt(bitPattern: self.attachmentPointer.uniqueId.hash)
    }

    override func mediaViewDisplaySize() -> CGSize {
        return CGSize(width: 200, height: 90)
    }

    override func mediaView() -> UIView? {
        guard self.cachedView == nil else {
            return self.cachedView
        }

        let frame = CGRect(origin: CGPoint.zero, size: self.mediaViewDisplaySize())
        let view = UIView(frame: frame)
        self.cachedView = view

        JSQMessagesMediaViewBubbleImageMasker.applyBubbleImageMask(toMediaView: view, isOutgoing:!isIncoming)

        view.isUserInteractionEnabled = false
        view.clipsToBounds = true

        let attachmentPointerView = AttachmentPointerView(attachmentPointer: attachmentPointer, isIncoming: self.isIncoming)
        self.attachmentPointerView = attachmentPointerView
        view.addSubview(attachmentPointerView)

        attachmentPointerView.autoPinWidthToSuperview(withMargin: 20)
        attachmentPointerView.autoVCenterInSuperview()

        switch attachmentPointer.state {
        case .downloading:
            NotificationCenter.default.addObserver(self, selector: #selector(attachmentDownloadProgress), name: NSNotification.Name.attachmentDownloadProgress, object: nil)
            view.backgroundColor = isIncoming ? UIColor.jsq_messageBubbleLightGray() : UIColor.ows_fadedBlue()
        case .enqueued:
            view.backgroundColor = isIncoming ? UIColor.jsq_messageBubbleLightGray() : UIColor.ows_fadedBlue()
        case .failed:
            view.backgroundColor = UIColor.gray
        }

        return cachedView
    }

    func attachmentDownloadProgress(_ notification: NSNotification) {
        guard let attachmentPointerView = self.attachmentPointerView else {
            Logger.error("\(TAG) downloading view was unexpectedly nil for notification: \(notification)")
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
            attachmentPointerView.progress = progress
        }
    }
}
