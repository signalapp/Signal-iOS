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
        }
    }

    public var attributedSubtitle: NSAttributedString? {
        get {
            return self.subtitleLabel.attributedText
        }
        set {
            self.subtitleLabel.attributedText = newValue
        }
    }

    public var avatarImage: UIImage? {
        get {
            return self.avatarView.image
        }
        set {
            self.avatarView.image = newValue
        }
    }

    public let titlePrimaryFont: UIFont =  UIFont.ows_boldFont(withSize: 17)
    public let titleSecondaryFont: UIFont =  UIFont.ows_regularFont(withSize: 9)

    public let subtitleFont: UIFont = UIFont.ows_regularFont(withSize: 12)
    private let titleLabel: UILabel
    private let subtitleLabel: UILabel
    private let avatarView: AvatarImageView

    public required init(thread: TSThread, contactsManager: OWSContactsManager) {

        let avatarView = ConversationAvatarImageView(thread: thread, diameter: 36, contactsManager: contactsManager)
        self.avatarView = avatarView
        // remove default border on avatarView
        avatarView.layer.borderWidth = 0

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

        let textRows = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textRows.axis = .vertical
        textRows.alignment = .leading
        textRows.distribution = .fillProportionally
        textRows.spacing = 0

        textRows.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        textRows.isLayoutMarginsRelativeArrangement = true

        // low content hugging so that the text rows push container to the right bar button item(s)
        textRows.setContentHuggingLow()

        super.init(frame: .zero)

        self.layoutMargins = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
        self.isLayoutMarginsRelativeArrangement = true

        self.axis = .horizontal
        self.alignment = .center
        self.spacing = 0
        self.addArrangedSubview(avatarView)
        self.addArrangedSubview(textRows)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapView))
        self.addGestureRecognizer(tapGesture)
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required public override init(frame: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        // Grow to fill as much of the navbar as possible.
        return UILayoutFittingExpandedSize
    }

    // MARK: Delegate Methods

    @objc func didTapView(tapGesture: UITapGestureRecognizer) {
        guard tapGesture.state == .recognized else {
            return
        }

        self.delegate?.didTapConversationHeaderView(self)
    }
}
