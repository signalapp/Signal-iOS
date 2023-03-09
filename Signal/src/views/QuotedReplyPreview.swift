//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

@objc protocol QuotedReplyPreviewCancelDelegate: AnyObject {
    func quotedReplyPreviewDidPressCancel()
}

class QuotedReplyPreview: UIView, OWSQuotedMessageViewDelegate {

    private weak var cancelDelegate: QuotedReplyPreviewCancelDelegate!

    private let quotedReply: OWSQuotedReplyModel
    private let conversationStyle: ConversationStyle
    private var quotedMessageView: OWSQuotedMessageView?
    private var heightConstraint: NSLayoutConstraint!

    @available(*, unavailable, message: "use other constructor instead.")
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use other constructor instead.")
    override init(frame: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    init(quotedReply: OWSQuotedReplyModel,
         conversationStyle: ConversationStyle,
         cancelDelegate: QuotedReplyPreviewCancelDelegate) {
        self.quotedReply = quotedReply
        self.conversationStyle = conversationStyle
        self.cancelDelegate = cancelDelegate

        super.init(frame: .zero)

        self.heightConstraint = self.autoSetDimension(.height, toSize: 0)

        updateContents()

        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    private let draftMarginTop: CGFloat = 6

    func updateContents() {
        subviews.forEach { $0.removeFromSuperview() }

        let hMargin: CGFloat = 6
        self.layoutMargins = UIEdgeInsets(top: draftMarginTop,
                                          left: hMargin,
                                          bottom: 0,
                                          right: hMargin)

        // We instantiate quotedMessageView late to ensure that it is updated
        // every time contentSizeCategoryDidChange (i.e. when dynamic type
        // sizes changes).
        let quotedMessageView = OWSQuotedMessageView(forPreview: quotedReply, conversationStyle: conversationStyle)
        quotedMessageView.delegate = self
        quotedMessageView.cancelDelegate = self.cancelDelegate
        self.quotedMessageView = quotedMessageView
        quotedMessageView.setContentHuggingHorizontalLow()
        quotedMessageView.setCompressionResistanceHorizontalLow()
        quotedMessageView.backgroundColor = .clear
        self.addSubview(quotedMessageView)
        quotedMessageView.autoPinEdgesToSuperviewMargins()

        updateHeight()
    }

    // MARK: Sizing

    func updateHeight() {
        guard let quotedMessageView = quotedMessageView else {
            owsFailDebug("missing quotedMessageView")
            return
        }
        let size = quotedMessageView.size(forMaxWidth: CGFloat.infinity)
        self.heightConstraint.constant = size.height + draftMarginTop
    }

    @objc
    func contentSizeCategoryDidChange(_ notification: Notification) {
        Logger.debug("")

        updateContents()
    }

    // MARK: - OWSQuotedMessageViewDelegate

    @objc
    public func didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel, failedThumbnailDownloadAttachmentPointer attachmentPointer: TSAttachmentPointer) {
        // Do nothing.
    }
}
