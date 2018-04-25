//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol ConversationHeaderViewDelegate {
    func didTapConversationHeaderView(_ conversationHeaderView: ConversationHeaderView)
}

@objc
public class ConversationHeaderView: UIStackView {

    public weak var delegate: ConversationHeaderViewDelegate?

    public var attributedTitle: NSAttributedString? {
        get {
            return self.titleLabel.attributedText
        }
        set {
            self.titleLabel.attributedText = newValue
//            self.layoutIfNeeded()
//            self.titleLabel.sizeToFit()
//            self.sizeToFit()
        }
    }

    public var attributedSubtitle: NSAttributedString? {
        get {
            return self.subtitleLabel.attributedText
        }
        set {
            self.subtitleLabel.attributedText = newValue
//            self.layoutIfNeeded()
//            self.subtitleLabel.sizeToFit()
//            self.sizeToFit()
        }
    }

    public let titlePrimaryFont: UIFont =  UIFont.ows_boldFont(withSize: 20)
    public let titleSecondaryFont: UIFont =  UIFont.ows_regularFont(withSize: 11)

    public let subtitleFont: UIFont = UIFont.ows_regularFont(withSize: 12)
//    public let columns: UIStackView
//    public let textRows: UIStackView
    private let titleLabel: UILabel
    private let subtitleLabel: UILabel

    override init(frame: CGRect) {

        // TODO
//        let avatarView: UIImageView = UIImageView()

        titleLabel = UILabel()
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = titlePrimaryFont
        titleLabel.setContentHuggingHigh()

        subtitleLabel = UILabel()
        subtitleLabel.textColor = .white
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = subtitleFont
        subtitleLabel.setContentHuggingHigh()

//        textRows = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
//        textRows.axis = .vertical
//        textRows.alignment = .leading

//        columns = UIStackView(arrangedSubviews: [avatarView, textRows])

        super.init(frame: frame)

        // needed for proper layout on iOS10
        self.translatesAutoresizingMaskIntoConstraints = false

        self.axis = .vertical
        self.distribution = .fillProportionally
        self.alignment = .leading
        self.spacing = 0
        self.addArrangedSubview(titleLabel)
        self.addArrangedSubview(subtitleLabel)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapView))
        self.addGestureRecognizer(tapGesture)

//        titleLabel.setCompressionResistanceHigh()
//        subtitleLabel.setCompressionResistanceHigh()
//        self.setCompressionResistanceHigh()
//        self.setContentHuggingLow()

//        self.layoutIfNeeded()
//        sizeToFit()
//
//        self.translatesAutoresizingMaskIntoConstraints = true

//        self.addSubview(columns)
//        columns.autoPinEdgesToSuperviewEdges()
//        self.addRedBorderRecursively()
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        // Grow to fill as much of the navbar as possible.
        if #available(iOS 11, *) {
            return UILayoutFittingExpandedSize
        } else {
            return super.intrinsicContentSize
        }
    }

    // MARK: Delegate Methods

    func didTapView(tapGesture: UITapGestureRecognizer) {
        guard tapGesture.state == .recognized else {
            return
        }

        self.delegate?.didTapConversationHeaderView(self)
    }
}
