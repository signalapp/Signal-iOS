//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentModelCell: UITableViewCell {
    static let reuseIdentifier = "PaymentModelCell"

    let contactAvatarView = ConversationAvatarView(sizeClass: avatarSizeClass, localUserDisplayMode: .asUser)
    let nameLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.font = .dynamicTypeBodyClamped
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    let statusLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeSubheadlineClamped
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    let amountLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBodyClamped
        label.adjustsFontForContentSizeCategory = true
        label.setCompressionResistanceHigh()
        label.setContentHuggingHigh()
        return label
    }()

    let hStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = PaymentModelCell.hStackSpacing
        return stackView
    }()

    lazy var vStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [nameLabel, statusLabel])
        stackView.axis = .vertical
        stackView.alignment = .fill
        return stackView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        OWSTableItem.configureCell(self)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static var avatarSizeClass = ConversationAvatarView.Configuration.SizeClass.thirtySix

    private static var hStackSpacing: CGFloat = 12

    static var separatorInsetLeading: CGFloat {
        CGFloat(avatarSizeClass.diameter) + hStackSpacing
    }

    func configure(paymentItem: PaymentsHistoryItem) {
        var avatarView: UIView
        if let address = paymentItem.address {
            contactAvatarView.updateWithSneakyTransactionIfNecessary { config in
                config.dataSource = .address(address)
            }
            avatarView = contactAvatarView
        } else {
            let avatarSize = Self.avatarSizeClass.diameter
            avatarView = PaymentsUI.buildUnidentifiedTransactionAvatar(avatarSize: avatarSize)
        }
        if paymentItem.isUnread {
            let avatarWrapper = UIView.container()
            avatarWrapper.addSubview(avatarView)
            avatarView.autoPinEdgesToSuperviewEdges()
            avatarView = avatarWrapper
            avatarView.addCircleBadge(color: .Signal.accent)
        }
        hStack.addArrangedSubview(avatarView)

        nameLabel.text = paymentItem.displayName
        statusLabel.text = paymentItem.statusDescription(isLongForm: false)
        hStack.addArrangedSubview(vStack)

        // We don't want to render the amount for incoming
        // transactions until they are verified.
        amountLabel.text = paymentItem.formattedPaymentAmount
        amountLabel.textColor = paymentItem.isIncoming ? .Signal.green : .Signal.label
        hStack.addArrangedSubview(amountLabel)

        accessoryType = .disclosureIndicator
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        contactAvatarView.reset()
        hStack.removeAllSubviews()
    }
}
