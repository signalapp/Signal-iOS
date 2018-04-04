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
    public weak var delegate: QuotedReplyPreviewDelegate?

    private class func iconView(message: TSQuotedMessage) -> UIView? {
        guard let contentType = message.contentType else {
            return nil
        }

        let iconText = TSAttachmentStream.emoji(forMimeType: contentType)

        let label = UILabel()
        label.setContentHuggingHigh()
        label.text = iconText

        return label
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(quotedMessage: TSQuotedMessage) {
        super.init(frame: .zero)

        let isQuotingSelf = quotedMessage.authorId == TSAccountManager.localNumber()

        // used for stripe and author
        // FIXME actual colors TBD
        let authorColor: UIColor = isQuotingSelf ? .ows_materialBlue : .black

        // used for text and cancel
        let foregroundColor: UIColor = .darkGray

        let  authorLabel: UILabel = UILabel()
        authorLabel.textColor = authorColor
        authorLabel.text = Environment.current().contactsManager.displayName(forPhoneIdentifier: quotedMessage.authorId)
        authorLabel.font = .ows_dynamicTypeHeadline

        let bodyLabel: UILabel = UILabel()
        bodyLabel.textColor = foregroundColor
        bodyLabel.font = .ows_footnote
        bodyLabel.text = quotedMessage.body

        let iconView: UIView? = QuotedReplyPreview.iconView(message: quotedMessage)

        let cancelButton: UIButton = UIButton(type: .custom)
        // FIXME proper image asset/size
        let buttonImage: UIImage = #imageLiteral(resourceName: "quoted-message-cancel").withRenderingMode(.alwaysTemplate)
        cancelButton.setImage(buttonImage, for: .normal)
        cancelButton.imageView?.tintColor = foregroundColor
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

        let quoteStripe: UIView = UIView()
        quoteStripe.backgroundColor = authorColor

        let contentViews: [UIView] = iconView == nil ? [bodyLabel] : [iconView!, bodyLabel]
        let contentContainer: UIStackView = UIStackView(arrangedSubviews: contentViews)
        contentContainer.axis = .horizontal
        contentContainer.spacing = 4.0

        self.addSubview(authorLabel)
        self.addSubview(contentContainer)
        self.addSubview(cancelButton)
        self.addSubview(quoteStripe)

        // Layout

        let kCancelButtonMargin: CGFloat = 4
        let kQuoteStripeWidth: CGFloat = 4
        let leadingMargin: CGFloat = kQuoteStripeWidth + 8
        let vMargin: CGFloat = 6
        let trailingMargin: CGFloat = 8

        self.layoutMargins = UIEdgeInsets(top: vMargin, left: leadingMargin, bottom: vMargin, right: trailingMargin)

        quoteStripe.autoPinEdge(toSuperviewEdge: .leading)
        quoteStripe.autoPinHeightToSuperview()
        quoteStripe.autoSetDimension(.width, toSize: kQuoteStripeWidth)

        authorLabel.autoPinTopToSuperviewMargin()
        authorLabel.autoPinLeadingToSuperviewMargin()

        authorLabel.autoPinEdge(.trailing, to: .leading, of: cancelButton, withOffset: -kCancelButtonMargin)
        authorLabel.setCompressionResistanceHigh()

        contentContainer.autoPinLeadingToSuperviewMargin()
        contentContainer.autoPinBottomToSuperviewMargin()
        contentContainer.autoPinEdge(.top, to: .bottom, of: authorLabel)
        contentContainer.autoPinEdge(.trailing, to: .leading, of: cancelButton, withOffset: -kCancelButtonMargin)

        cancelButton.autoPinTrailingToSuperviewMargin()
        cancelButton.autoVCenterInSuperview()
        cancelButton.setContentHuggingHigh()

        cancelButton.autoSetDimensions(to: CGSize(width: 40, height: 40))
    }

    // MARK: UIViewOverrides

    // Used by stack view to determin size.
    override var intrinsicContentSize: CGSize {
        return CGSize(width: 0, height: 30)
    }

    // MARK: Actions
    @objc
    func didTapCancel(_ sender: Any) {
        self.delegate?.quotedReplyPreviewDidPressCancel(self)
    }
}
