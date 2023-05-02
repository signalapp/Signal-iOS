//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

@objc
public protocol ConversationHeaderViewDelegate {
    func didTapConversationHeaderView(_ conversationHeaderView: ConversationHeaderView)
    func didTapConversationHeaderViewAvatar(_ conversationHeaderView: ConversationHeaderView)
}

public class ConversationHeaderView: UIView {

    public weak var delegate: ConversationHeaderViewDelegate?

    public var attributedTitle: NSAttributedString? {
        get {
            return self.titleLabel.attributedText
        }
        set {
            self.titleLabel.attributedText = newValue
        }
    }

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

    public var attributedSubtitle: NSAttributedString? {
        get {
            return self.subtitleLabel.attributedText
        }
        set {
            self.subtitleLabel.attributedText = newValue
            self.subtitleLabel.isHidden = newValue == nil
        }
    }

    public let titlePrimaryFont = UIFont.semiboldFont(ofSize: 17)
    public let titleSecondaryFont = UIFont.regularFont(ofSize: 9)
    public let subtitleFont = UIFont.regularFont(ofSize: 12)

    private let titleLabel: UILabel
    private let titleIconView: UIImageView
    private let subtitleLabel: UILabel

    private var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass {
        traitCollection.verticalSizeClass == .compact ? .twentyFour : .thirtySix
    }
    private(set) lazy var avatarView = ConversationAvatarView(
        sizeClass: avatarSizeClass,
        localUserDisplayMode: .noteToSelf)

    public required init() {
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
        // There is a strange bug where an initial height of 0
        // breaks the layout, so set an initial height.
        titleColumns.autoSetDimension(
            .height,
            toSize: titleLabel.font.lineHeight,
            relation: .greaterThanOrEqual
        )

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

        let rootStack = UIStackView()
        rootStack.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        rootStack.isLayoutMarginsRelativeArrangement = true

        rootStack.axis = .horizontal
        rootStack.alignment = .center
        rootStack.spacing = 0
        rootStack.addArrangedSubview(avatarView)
        rootStack.addArrangedSubview(textRows)

        addSubview(rootStack)
        rootStack.autoPinEdgesToSuperviewEdges()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapView))
        rootStack.addGestureRecognizer(tapGesture)

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .themeDidChange, object: nil)
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required public override init(frame: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public func configure(threadViewModel: ThreadViewModel) {
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .thread(threadViewModel.threadRecord)
            config.storyConfiguration = .autoUpdate()
            config.applyConfigurationSynchronously()
        }
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

    public func updateAvatar() {
        avatarView.reloadDataIfNecessary()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.sizeClass = avatarSizeClass
        }
    }

    // MARK: Delegate Methods

    @objc
    func didTapView(tapGesture: UITapGestureRecognizer) {
        guard tapGesture.state == .recognized else {
            return
        }

        if avatarView.bounds.contains(tapGesture.location(in: avatarView)) {
            self.delegate?.didTapConversationHeaderViewAvatar(self)
        } else {
            self.delegate?.didTapConversationHeaderView(self)
        }
    }
}
