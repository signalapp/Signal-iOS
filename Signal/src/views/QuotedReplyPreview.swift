//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol QuotedReplyPreviewDelegate: class {
    func quotedReplyPreviewDidPressCancel(_ preview: QuotedReplyPreview)
}

@objc
class QuotedReplyPreview: UIStackView {
    @objc
    public weak var delegate: QuotedReplyPreviewDelegate?

    private let quotedReply: OWSQuotedReplyModel
    private let conversationStyle: ConversationStyle
    private var quotedMessageView: OWSQuotedMessageView?
    private var heightConstraint: NSLayoutConstraint!

    @available(*, unavailable, message:"use other constructor instead.")
    required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    override init(frame: CGRect) {
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

    private let draftMarginTop: CGFloat = 6

    func updateContents() {
        subviews.forEach { $0.removeFromSuperview() }

        // We instantiate quotedMessageView late to ensure that it is updated
        // every time contentSizeCategoryDidChange (i.e. when dynamic type
        // sizes changes).
        let quotedMessageView = OWSQuotedMessageView(forPreview: quotedReply, conversationStyle: conversationStyle)
        self.quotedMessageView = quotedMessageView
        quotedMessageView.setContentHuggingHorizontalLow()
        quotedMessageView.setCompressionResistanceHorizontalLow()

        quotedMessageView.backgroundColor = .clear

        let cancelButton: UIButton = UIButton(type: .custom)

        let cancelImage = UIImage(named: "compose-cancel")?.withRenderingMode(.alwaysTemplate)
        cancelButton.setImage(cancelImage, for: .normal)
        cancelButton.imageView?.tintColor = Theme.secondaryColor
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        if let cancelSize = cancelImage?.size {
            cancelButton.autoSetDimensions(to: cancelSize)
        }

        self.axis = .horizontal
        self.alignment = .fill
        self.distribution = .fill
        self.spacing = 8
        self.isLayoutMarginsRelativeArrangement = true
        let hMarginLeading: CGFloat = 6
        let hMarginTrailing: CGFloat = 12
        self.layoutMargins = UIEdgeInsets(top: draftMarginTop,
                                          left: CurrentAppContext().isRTL ? hMarginTrailing : hMarginLeading,
                                          bottom: 0,
                                          right: CurrentAppContext().isRTL ? hMarginLeading : hMarginTrailing)

        self.addArrangedSubview(quotedMessageView)

        let cancelStack = UIStackView()
        cancelStack.axis = .horizontal
        cancelStack.alignment = .top
        cancelStack.setContentHuggingHigh()
        cancelStack.setCompressionResistanceHigh()
        cancelStack.addArrangedSubview(cancelButton)
        self.addArrangedSubview(cancelStack)

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
