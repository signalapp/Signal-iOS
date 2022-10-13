//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct NameCollisionCellModel {
    let address: SignalServiceAddress
    let name: String

    let oldName: String?
    let updateTimestamp: UInt64?

    let commonGroupsString: String
    let avatar: UIImage?
    let isBlocked: Bool
    let isSystemContact: Bool

    var phoneNumber: String? {
        address.phoneNumber.map {
            PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: $0)
        }
    }
}

extension NameCollision {
    private func avatar(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> UIImage? {
        if address.isLocalAddress, let localProfileAvatar = profileManager.localProfileAvatarImage() {
            return localProfileAvatar
        } else {
            return Self.avatarBuilder.avatarImage(forAddress: address,
                                                  diameterPoints: 64,
                                                  localUserDisplayMode: .asUser,
                                                  transaction: transaction)
        }
    }

    private func commonGroupsString(
        for address: SignalServiceAddress,
        thread: TSThread,
        transaction: SDSAnyReadTransaction) -> String {

        let commonGroups = TSGroupThread.groupThreads(with: address, transaction: transaction)
        switch (thread, commonGroups.count) {
        case (_, 2...):
            let formatString = NSLocalizedString(
                "MANY_GROUPS_IN_COMMON_%d", tableName: "PluralAware",
                comment: "A string describing that the user has many groups in common with another user. Embeds {{common group count}}")
            return String.localizedStringWithFormat(formatString, commonGroups.count)

        case (is TSContactThread, 1):
            let formatString = NSLocalizedString(
                "THREAD_DETAILS_ONE_MUTUAL_GROUP",
                comment: "A string indicating a mutual group the user shares with this contact. Embeds {{mutual group name}}")
            return String(format: formatString, commonGroups[0].groupNameOrDefault)

        case (is TSGroupThread, 1):
            return NSLocalizedString(
                "NO_OTHER_GROUPS_IN_COMMON",
                comment: "A string describing that the user has no groups in common other than the group implied by the current UI context")

        case (is TSContactThread, 0):
            return NSLocalizedString(
                "NO_GROUPS_IN_COMMON",
                comment: "A string describing that the user has no groups in common with another user")

        default:
            owsFailDebug("Unexpected common group count")
            return ""
        }
    }

    func collisionCellModels(thread: TSThread, transaction: SDSAnyReadTransaction) -> [NameCollisionCellModel] {
        elements.map {
            NameCollisionCellModel(
                address: $0.address,
                name: $0.currentName,
                oldName: $0.oldName,
                updateTimestamp: $0.latestUpdateTimestamp,
                commonGroupsString: commonGroupsString(for: $0.address, thread: thread, transaction: transaction),
                avatar: avatar(for: $0.address, transaction: transaction),
                isBlocked: blockingManager.isAddressBlocked($0.address, transaction: transaction),
                isSystemContact: Self.contactsManager.isSystemContact(address: $0.address, transaction: transaction)
            )
        }
    }
}

class NameCollisionCell: UITableViewCell {
    typealias Action = (title: String, action: () -> Void)

    let avatarView = ConversationAvatarView(sizeClass: .sixtyFour, localUserDisplayMode: .asUser)
    let nameLabel: UILabel = {
        let label = UILabel()

        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_dynamicTypeBody
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0

        return label
    }()

    let phoneNumberLabel: UILabel = {
        let label = UILabel()

        label.textColor = Theme.secondaryTextAndIconColor
        label.font = UIFont.ows_dynamicTypeFootnote
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0

        return label
    }()

    let blockedLabel: UILabel = {
        let label = UILabel()

        label.textColor = Theme.secondaryTextAndIconColor
        label.font = UIFont.ows_dynamicTypeFootnote
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.text = NSLocalizedString(
            "CONTACT_CELL_IS_BLOCKED",
            comment: "An indicator that a contact or group has been blocked.")

        return label
    }()

    let commonGroupsLabel: UILabel = {
        let label = UILabel()

        label.textColor = Theme.secondaryTextAndIconColor
        label.font = UIFont.ows_dynamicTypeFootnote
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0

        return label
    }()

    let nameChangeSpacer = UIView.spacer(withHeight: 12)

    let recentNameChangeLabel: UILabel = {
        let label = UILabel()

        label.textColor = Theme.secondaryTextAndIconColor
        label.font = UIFont.ows_dynamicTypeFootnote.ows_italic
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0

        return label
    }()

    let separatorView: UIView = {
        let hairline = UIView()
        hairline.backgroundColor = Theme.cellSeparatorColor
        hairline.autoSetDimension(.height, toSize: CGHairlineWidth())
        let separator = UIView()
        separator.addSubview(hairline)
        hairline.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 0, vMargin: 12))
        return separator
    }()

    let actionStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }()

    required override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let verticalStack = UIStackView(arrangedSubviews: [
            nameLabel,
            phoneNumberLabel,
            blockedLabel,
            commonGroupsLabel,
            nameChangeSpacer,
            recentNameChangeLabel,
            UIView.vStretchingSpacer(),
            separatorView,
            actionStack
        ])
        let horizontalStack = UIStackView(arrangedSubviews: [
            avatarView, verticalStack
        ])

        verticalStack.axis = .vertical
        verticalStack.spacing = 1
        horizontalStack.axis = .horizontal
        horizontalStack.spacing = 16
        horizontalStack.alignment = .top

        contentView.addSubview(horizontalStack)
        horizontalStack.autoPinEdgesToSuperviewMargins()
        separatorView.autoConstrainAttribute(.horizontal, to: .bottom, of: avatarView, withMultiplier: 1, relation: .greaterThanOrEqual)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func createWithModel(
        _ model: NameCollisionCellModel,
        actions: [NameCollisionCell.Action]) -> Self {

        let cell = self.init(style: .default, reuseIdentifier: nil)
        cell.configure(model: model, actions: actions)
        return cell
    }

    override func prepareForReuse() {
        avatarView.reset()
        nameLabel.text = ""
        phoneNumberLabel.text = ""
        blockedLabel.isHidden = true
        commonGroupsLabel.text = ""
        nameChangeSpacer.isHidden = false
        recentNameChangeLabel.text = ""
    }

    func configure(model: NameCollisionCellModel, actions: [NameCollisionCell.Action]) {
        owsAssertDebug(actions.count < 3, "Only supports two actions. Feel free to update this for more.")

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(model.address)
        }
        if model.address.isLocalAddress {
            nameLabel.text = CommonStrings.you
        } else {
            nameLabel.text = model.name
        }

        if let phoneNumber = model.phoneNumber {
            phoneNumberLabel.text = phoneNumber
        } else {
            phoneNumberLabel.isHidden = true
        }
        blockedLabel.isHidden = !model.isBlocked
        commonGroupsLabel.isHidden = model.address.isLocalAddress
        commonGroupsLabel.text = model.commonGroupsString

        if let oldName = model.oldName {
            nameChangeSpacer.isHidden = false
            recentNameChangeLabel.isHidden = false
            let formatString = NSLocalizedString(
                "NAME_COLLISION_RECENT_CHANGE_FORMAT_STRING",
                comment: "Format string describing a recent profile name change that led to a name collision. Embeds {{ %1$@ old profile name }} and {{ %2$@ current profile name }}")
            recentNameChangeLabel.text = String(format: formatString, oldName, model.name)
        } else {
            nameChangeSpacer.isHidden = true
            recentNameChangeLabel.isHidden = true
        }

        actionStack.removeAllSubviews()
        let buttons = actions.map { createButton(for: $0) }
        buttons.forEach { actionStack.addArrangedSubview($0) }
        actionStack.addArrangedSubview(UIView.vStretchingSpacer())

        // If one button grows super tall, its larger intrinsic content size could result in the other button
        // being compressed very thin and tall in response. It's unlikely, since this would only be hit by a very
        // edge case localization. But, if it does happen, these constraints ensure things will look reasonably okay.
        if let button1 = buttons[safe: 0], let button2 = buttons[safe: 1] {
            button1.autoSetDimension(.width, toSize: min(100, button1.intrinsicContentSize.width), relation: .greaterThanOrEqual)
            button2.autoSetDimension(.width, toSize: min(100, button2.intrinsicContentSize.width), relation: .greaterThanOrEqual)
        }

        separatorView.isHidden = actions.isEmpty
        actionStack.isHidden = actions.isEmpty
    }

    private func createButton(for action: Action) -> UIButton {
        let button = OWSButton(title: action.title, block: action.action)
        button.setTitleColor(Theme.accentBlueColor, for: .normal)
        button.setTitleColor(Theme.accentBlueColor.withAlphaComponent(0.7), for: .highlighted)
        button.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.contentHorizontalAlignment = .leading

        // By default, a button's label will grow outside of the buttons bounds
        button.titleLabel?.autoMatch(.height, to: .height, of: button, withMultiplier: 1, relation: .lessThanOrEqual)
        button.setContentHuggingHorizontalHigh()
        return button
    }
}
