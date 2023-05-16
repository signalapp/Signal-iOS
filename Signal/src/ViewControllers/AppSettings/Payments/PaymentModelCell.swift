//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public class PaymentModelCell: UITableViewCell {
    static let reuseIdentifier = "PaymentModelCell"

    let contactAvatarView = ConversationAvatarView(sizeClass: avatarSizeClass, localUserDisplayMode: .asUser)
    let nameLabel = UILabel()
    let statusLabel = UILabel()
    let amountLabel = UILabel()
    let hStack = UIStackView()
    let vStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        OWSTableItem.configureCell(self)
        backgroundColor = .clear
        selectionStyle = .none

        amountLabel.setCompressionResistanceHigh()
        amountLabel.setContentHuggingHigh()

        vStack.addArrangedSubview(nameLabel)
        vStack.addArrangedSubview(statusLabel)
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.setContentHuggingHorizontalLow()

        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.distribution = .fill
        hStack.spacing = Self.hStackSpacing
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static var avatarSizeClass = ConversationAvatarView.Configuration.SizeClass.thirtySix

    private static var hStackSpacing: CGFloat = 12

    public static var separatorInsetLeading: CGFloat {
        CGFloat(avatarSizeClass.diameter) + hStackSpacing
    }

    func configure(paymentItem: PaymentsHistoryItem) {

        let paymentModel = paymentItem.paymentModel

        var arrangedSubviews = [UIView]()

        nameLabel.font = .dynamicTypeBodyClamped
        nameLabel.textColor = Theme.primaryTextColor

        statusLabel.font = .dynamicTypeSubheadlineClamped
        statusLabel.textColor = Theme.ternaryTextColor

        amountLabel.font = .dynamicTypeBodyClamped
        amountLabel.textColor = (paymentItem.isIncoming
                                    ? UIColor.ows_accentGreen
                                    : Theme.primaryTextColor)

        var avatarView: UIView
        if let address = paymentItem.address {
            contactAvatarView.updateWithSneakyTransactionIfNecessary { config in
                config.dataSource = .address(address)
            }
            avatarView = contactAvatarView
        } else {
            owsAssertDebug(paymentItem.isUnidentified ||
                            paymentItem.isOutgoingTransfer ||
                            paymentItem.isDefragmentation)

            let avatarSize = Self.avatarSizeClass.diameter
            avatarView = PaymentsViewUtils.buildUnidentifiedTransactionAvatar(avatarSize: avatarSize)
        }
        if paymentModel.isUnread {
            let avatarWrapper = UIView.container()
            avatarWrapper.addSubview(avatarView)
            avatarView.autoPinEdgesToSuperviewEdges()
            avatarView = avatarWrapper
            PaymentsViewUtils.addUnreadBadge(toView: avatarView)
        }
        arrangedSubviews.append(avatarView)

        nameLabel.text = paymentItem.displayName

        // We don't want to render the amount for incoming
        // transactions until they are verified.
        if let paymentAmount = paymentModel.paymentAmount {
            var totalAmount = paymentAmount
            if let feeAmount = paymentModel.mobileCoin?.feeAmount {
                totalAmount = totalAmount.plus(feeAmount)
            }
            amountLabel.text = PaymentsFormat.format(paymentAmount: totalAmount,
                                                     isShortForm: true,
                                                     withCurrencyCode: true,
                                                     withSpace: false,
                                                     withPaymentType: paymentModel.paymentType)
        } else {
            amountLabel.text = ""
        }

        arrangedSubviews.append(vStack)
        arrangedSubviews.append(amountLabel)
        hStack.removeAllSubviews()
        for subview in arrangedSubviews {
            hStack.addArrangedSubview(subview)
        }

        statusLabel.text = paymentModel.statusDescription(isLongForm: false)

        accessoryType = .disclosureIndicator
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        contactAvatarView.reset()
        nameLabel.text = nil
        statusLabel.text = nil
        amountLabel.text = nil
    }
}
