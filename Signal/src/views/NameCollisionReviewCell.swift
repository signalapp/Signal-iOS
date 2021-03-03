//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
        if address.isLocalAddress, let localProfileAvatar = OWSProfileManager.shared().localProfileAvatarImage() {
            return localProfileAvatar.resizedImage(to: CGSize(square: 64))
        } else {
            return OWSContactAvatarBuilder.buildImage(
                address: address,
                diameter: 64,
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
                "MANY_GROUPS_IN_COMMON",
                comment: "A string describing that the user has many groups in common with another user. Embeds {{common group count}}")
            return String(format: formatString, String(commonGroups.count))

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
                isBlocked: OWSBlockingManager.shared().isAddressBlocked($0.address),
                isSystemContact: Environment.shared.contactsManager.isSystemContact(address: $0.address)
            )
        }
    }
}

class NameCollisionReviewContactCell: UITableViewCell {
    let avatarView = AvatarImageView()

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

    // Rolling our own cell separator. It should be aligned with the name/actions (which is pinned to the safe area)
    // The separator UITableView provides does not respect safe area. By handling this ourselves it can now respect
    // safe area. Additionally it makes the alignment a bit more explicit.
    let separatorHairline: UIView = {
        let separator = UIView()
        separator.backgroundColor = Theme.cellSeparatorColor
        separator.autoSetDimension(.height, toSize: CGHairlineWidth())
        return separator
    }()

    required override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let verticalStack = UIStackView(arrangedSubviews: [
            nameLabel, phoneNumberLabel, blockedLabel, commonGroupsLabel, nameChangeSpacer, recentNameChangeLabel
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
        horizontalStack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
        verticalStack.autoPinEdge(.bottom, to: .bottom, of: contentView, withOffset: -12, relation: .lessThanOrEqual)
        avatarView.autoSetDimensions(to: CGSize(square: 64))

        contentView.addSubview(separatorHairline)
        separatorHairline.autoPinLeading(toEdgeOf: verticalStack)
        separatorHairline.autoPinTrailing(toEdgeOf: contentView)
        separatorHairline.autoPinEdge(.bottom, to: .bottom, of: contentView)

        isPairedWithActions = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func createWithModel(_ model: NameCollisionCellModel) -> Self {
        let cell = self.init(style: .default, reuseIdentifier: nil)
        cell.configure(model: model)
        return cell
    }

    override func prepareForReuse() {
        avatarView.image = nil
        nameLabel.text = ""
        phoneNumberLabel.text = ""
        blockedLabel.isHidden = true
        commonGroupsLabel.text = ""
        nameChangeSpacer.isHidden = false
        recentNameChangeLabel.text = ""
    }

    func configure(model: NameCollisionCellModel) {
        avatarView.image = model.avatar
        if model.address.isLocalAddress {
            nameLabel.text = NSLocalizedString("GROUP_MEMBER_LOCAL_USER", comment: "Label indicating the local user.")
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
    }

    lazy var avatarBottomEdgeConstraint: NSLayoutConstraint = {
        avatarView.autoPinEdge(.bottom, to: .bottom, of: contentView, withOffset: -16, relation: .lessThanOrEqual)
    }()

    // If the cell is paired with actions, we don't need to pad the avatar view
    // If the cell is not paired with actions, we can hide our separator
    var isPairedWithActions: Bool = false {
        didSet {
            avatarBottomEdgeConstraint.isActive = !isPairedWithActions
            separatorHairline.isHidden = !isPairedWithActions
        }
    }
}

class NameCollisionActionCell: UITableViewCell {
    typealias Action = (title: String, action: () -> Void)

    init(actions: [Action]) {
        owsAssertDebug(actions.count < 3, "Only supports two actions. Feel free to update this for more.")

        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none
        let buttons = actions.map { createButton(for: $0) }

        let horizontalStack = UIStackView(arrangedSubviews: buttons + [UIView()])
        horizontalStack.axis = .horizontal
        horizontalStack.distribution = .equalSpacing
        horizontalStack.alignment = .center
        horizontalStack.spacing = 8

        // If one button grows super tall, its larger intrinsic content size could result in the other button
        // being compressed very thin and tall in response. It's unlikely, since this would only be hit by a very
        // edge case localization. But, if it does happen, things will look reasonably okay.
        if let button1 = buttons[safe: 0], let button2 = buttons[safe: 1] {
            button1.autoSetDimension(.width, toSize: min(100, button1.intrinsicContentSize.width), relation: .greaterThanOrEqual)
            button2.autoSetDimension(.width, toSize: min(100, button2.intrinsicContentSize.width), relation: .greaterThanOrEqual)
        }

        contentView.addSubview(horizontalStack)
        horizontalStack.autoPinEdge(toSuperviewEdge: .top, withInset: 8)
        horizontalStack.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
        horizontalStack.autoPinEdge(toSuperviewEdge: .leading, withInset: 96)
        horizontalStack.autoPinEdge(toSuperviewEdge: .trailing)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
