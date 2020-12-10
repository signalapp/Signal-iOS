//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol ConversationHeaderViewDelegate {
    func didTapConversationHeaderView(_ conversationHeaderView: ConversationHeaderView)
}

@objc
public class ConversationHeaderView: UIStackView {

    @objc
    public weak var delegate: ConversationHeaderViewDelegate?

    @objc
    public var attributedTitle: NSAttributedString? {
        get {
            return self.titleLabel.attributedText
        }
        set {
            self.titleLabel.attributedText = newValue
        }
    }

    @objc
    public var titleIcon: UIImage? {
        get {
            return self.titleIconView.image
        }
        set {
            self.titleIconView.image = newValue
            self.titleIconView.tintColor = Theme.secondaryTextAndIconColor
            self.titleIconView.isHidden = newValue == nil
        }
    }

    @objc
    public var attributedSubtitle: NSAttributedString? {
        get {
            return self.subtitleLabel.attributedText
        }
        set {
            self.subtitleLabel.attributedText = newValue
            self.subtitleLabel.isHidden = newValue == nil
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

    @objc
    public let titlePrimaryFont: UIFont =  UIFont.ows_semiboldFont(withSize: 17)
    @objc
    public let titleSecondaryFont: UIFont =  UIFont.ows_regularFont(withSize: 9)
    @objc
    public let subtitleFont: UIFont = UIFont.ows_regularFont(withSize: 12)

    private let titleLabel: UILabel
    private let titleIconView: UIImageView
    private let subtitleLabel: UILabel
    private let avatarView: ConversationAvatarImageView

    @objc
    public required init(thread: TSThread) {

        let avatarView = ConversationAvatarImageView(thread: thread, diameter: 36)
        self.avatarView = avatarView
        // remove default border on avatarView
        avatarView.layer.borderWidth = 0

        titleLabel = UILabel()
        titleLabel.textColor = Theme.navbarTitleColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = titlePrimaryFont
        titleLabel.setContentHuggingHigh()

        titleIconView = UIImageView()
        titleIconView.contentMode = .scaleAspectFit
        titleIconView.setCompressionResistanceHigh()

        let titleColumns = UIStackView(arrangedSubviews: [titleLabel, titleIconView])
        titleColumns.spacing = 5

        subtitleLabel = UILabel()
        subtitleLabel.textColor = Theme.navbarTitleColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = subtitleFont
        subtitleLabel.setContentHuggingHigh()

        let textRows = UIStackView(arrangedSubviews: [titleColumns, subtitleLabel])
        textRows.axis = .vertical
        textRows.alignment = .leading
        textRows.distribution = .fillProportionally
        textRows.spacing = 0

        textRows.layoutMargins = UIEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        textRows.isLayoutMarginsRelativeArrangement = true

        // low content hugging so that the text rows push container to the right bar button item(s)
        textRows.setContentHuggingLow()

        super.init(frame: .zero)

        self.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        self.isLayoutMarginsRelativeArrangement = true

        self.axis = .horizontal
        self.alignment = .center
        self.spacing = 0
        self.addArrangedSubview(avatarView)
        self.addArrangedSubview(textRows)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapView))
        self.addGestureRecognizer(tapGesture)

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .ThemeDidChange, object: nil)
    }

    required public init(coder: NSCoder) {
        notImplemented()
    }

    required public override init(frame: CGRect) {
        notImplemented()
    }

    public override var intrinsicContentSize: CGSize {
        // Grow to fill as much of the navbar as possible.
        return UIView.layoutFittingExpandedSize
    }

    @objc
    func themeDidChange() {
        titleLabel.textColor = Theme.navbarTitleColor
        subtitleLabel.textColor = Theme.navbarTitleColor
    }

    @objc
    public func updateAvatar() {
        databaseStorage.uiRead { transaction in
            self.avatarView.updateImage(transaction: transaction)
        }
    }

    // MARK: Delegate Methods

    @objc func didTapView(tapGesture: UITapGestureRecognizer) {
        guard tapGesture.state == .recognized else {
            return
        }

        self.delegate?.didTapConversationHeaderView(self)
    }
}
