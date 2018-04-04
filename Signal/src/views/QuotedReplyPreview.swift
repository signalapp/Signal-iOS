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

        let authorLabel: UILabel = UILabel()
        authorLabel.textColor = authorColor
        if isQuotingSelf {
            authorLabel.text = NSLocalizedString("MEDIA_GALLERY_SENDER_NAME_YOU", comment: "")
        } else {
            authorLabel.text = Environment.current().contactsManager.displayName(forPhoneIdentifier: quotedMessage.authorId)
        }
        authorLabel.font = .ows_dynamicTypeHeadline

        let bodyLabel: UILabel = UILabel()
        bodyLabel.textColor = foregroundColor
        bodyLabel.font = .ows_footnote

        bodyLabel.text = {
            if let contentType = quotedMessage.contentType {
                let emoji = TSAttachmentStream.emoji(forMimeType: contentType)
                return "\(emoji) \(quotedMessage.body ?? "")"
            } else {
                return quotedMessage.body
            }
        }()

        let thumbnailView: UIView? = {
            // FIXME TODO
//            if let image = quotedMessage.thumbnailImage() {
//                let imageView = UIImageView(image: image)
//                imageView.contentMode = .scaleAspectFill
//                imageView.autoPinToSquareAspectRatio()
//                imageView.layer.cornerRadius = 3.0
//                imageView.clipsToBounds = true
//
//                return imageView
//            }
            return nil
        }()

        let cancelButton: UIButton = UIButton(type: .custom)
        // FIXME proper image asset/size
        let buttonImage: UIImage = #imageLiteral(resourceName: "quoted-message-cancel").withRenderingMode(.alwaysTemplate)
        cancelButton.setImage(buttonImage, for: .normal)
        cancelButton.imageView?.tintColor = foregroundColor
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

        let quoteStripe: UIView = UIView()
        quoteStripe.backgroundColor = authorColor

        let textColumn = UIView.container()
        textColumn.addSubview(authorLabel)
        textColumn.addSubview(bodyLabel)

        authorLabel.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        authorLabel.autoPinEdge(.bottom, to: .top, of: bodyLabel)
        bodyLabel.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)

        let contentViews: [UIView] = [textColumn, thumbnailView, cancelButton].flatMap { return $0 }
        let contentRow = UIStackView(arrangedSubviews: contentViews)
        contentRow.axis = .horizontal
        self.addSubview(contentRow)
        self.addSubview(quoteStripe)

        // Layout

        let kQuoteStripeWidth: CGFloat = 4
        self.layoutMargins = UIEdgeInsets(top: 6,
                                          left: kQuoteStripeWidth + 8,
                                          bottom: 2,
                                          right: 4)

        quoteStripe.autoPinEdge(toSuperviewEdge: .leading)
        quoteStripe.autoPinHeightToSuperview()
        quoteStripe.autoSetDimension(.width, toSize: kQuoteStripeWidth)

        contentRow.autoPinEdgesToSuperviewMargins()

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
