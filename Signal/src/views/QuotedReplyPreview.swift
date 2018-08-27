//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol QuotedReplyPreviewDelegate: class {
    func quotedReplyPreviewDidPressCancel(_ preview: QuotedReplyPreview)
}

@objc
class QuotedReplyPreview: UIView {
    @objc
    public weak var delegate: QuotedReplyPreviewDelegate?

    private let quotedReply: OWSQuotedReplyModel
    private let conversationStyle: ConversationStyle
    private var quotedMessageView: OWSQuotedMessageView?
    private var heightConstraint: NSLayoutConstraint!

    @objc
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    init(quotedReply: OWSQuotedReplyModel, conversationStyle: ConversationStyle) {
        self.quotedReply = quotedReply
        self.conversationStyle = conversationStyle

        super.init(frame: .zero)

        self.heightConstraint = self.autoSetDimension(.height, toSize: 0)

        updateContents()

        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: .UIContentSizeCategoryDidChange, object: nil)
    }

    func updateContents() {
        subviews.forEach { $0.removeFromSuperview() }

        // We instantiate quotedMessageView late to ensure that it is updated
        // every time contentSizeCategoryDidChange (i.e. when dynamic type
        // sizes changes).
        let quotedMessageView = OWSQuotedMessageView(forPreview: quotedReply, conversationStyle: conversationStyle)
        self.quotedMessageView = quotedMessageView

        quotedMessageView.backgroundColor = .clear

        let cancelButton: UIButton = UIButton(type: .custom)

        let buttonImage: UIImage = #imageLiteral(resourceName: "quoted-message-cancel").withRenderingMode(.alwaysTemplate)
        cancelButton.setImage(buttonImage, for: .normal)
        cancelButton.imageView?.tintColor = Theme.secondaryColor
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

        self.layoutMargins = .zero

        self.addSubview(quotedMessageView)
        self.addSubview(cancelButton)

        quotedMessageView.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)
        cancelButton.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)
        cancelButton.autoPinEdge(.leading, to: .trailing, of: quotedMessageView)

        cancelButton.autoSetDimensions(to: CGSize(width: 40, height: 40))

        updateHeight()
    }

    // MARK: Actions

    @objc
    func didTapCancel(_ sender: Any) {
        self.delegate?.quotedReplyPreviewDidPressCancel(self)
    }

    // MARK: Sizing

    func updateHeight() {
        guard let quotedMessageView = quotedMessageView else {
            owsFailDebug("missing quotedMessageView")
            return
        }
        let size = quotedMessageView.size(forMaxWidth: CGFloat.infinity)
        self.heightConstraint.constant = size.height
    }

    @objc func contentSizeCategoryDidChange(_ notification: Notification) {
        Logger.debug("")

        updateContents()
    }
}
