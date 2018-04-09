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

    private let quotedReply: OWSQuotedReplyModel
    private var quotedMessageView: OWSQuotedMessageView
    private var heightConstraint: NSLayoutConstraint!

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(quotedReply: OWSQuotedReplyModel) {
        self.quotedReply = quotedReply
        self.quotedMessageView = OWSQuotedMessageView(forPreview: quotedReply)

        super.init(frame: .zero)

        self.heightConstraint = self.autoSetDimension(.height, toSize: 0)

        updateContents()

        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: .UIContentSizeCategoryDidChange, object: nil)
    }

    func updateContents() {
        subviews.forEach { $0.removeFromSuperview() }
        self.quotedMessageView = OWSQuotedMessageView(forPreview: quotedReply)

        quotedMessageView.backgroundColor = .clear

        let cancelButton: UIButton = UIButton(type: .custom)

        let buttonImage: UIImage = #imageLiteral(resourceName: "quoted-message-cancel").withRenderingMode(.alwaysTemplate)
        cancelButton.setImage(buttonImage, for: .normal)
        cancelButton.imageView?.tintColor = .darkGray
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
        let size = self.quotedMessageView.size(forMaxWidth: CGFloat.infinity)
        self.heightConstraint.constant = size.height
    }

    func contentSizeCategoryDidChange(_ notification: Notification) {
        Logger.debug("\(self.logTag) in \(#function)")

        updateContents()
    }
}
