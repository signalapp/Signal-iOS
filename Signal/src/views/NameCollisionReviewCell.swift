//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

struct NameCollisionCellModel {
    let address: SignalServiceAddress
    let name: String
    let shortName: String

    let profileNameChange: (oldestProfileName: String, newestProfileName: String)?
    let updateTimestamp: UInt64?

    /// The thread the collision appears in.
    /// Not necessarily the contacts thread for the address.
    let thread: TSThread
    let mutualGroups: [TSGroupThread]
    let isVerified: Bool
    let isConnection: Bool
    let isBlocked: Bool
    let hasPendingRequest: Bool
    let isSystemContact: Bool

    let viewControllerForPresentation: UIViewController
}

extension NameCollision {
    func collisionCellModels(
        thread: TSThread,
        identityManager: any OWSIdentityManager,
        profileManager: any ProfileManager,
        blockingManager: BlockingManager,
        contactsManager: any ContactManager,
        viewControllerForPresentation: UIViewController,
        tx: SDSAnyReadTransaction
    ) -> [NameCollisionCellModel] {
        elements.map {
            return NameCollisionCellModel(
                address: $0.address,
                name: $0.comparableName.resolvedValue(),
                shortName: $0.comparableName.resolvedValue(useShortNameIfAvailable: true),
                profileNameChange: $0.profileNameChange,
                updateTimestamp: $0.latestUpdateTimestamp,
                thread: thread,
                mutualGroups: TSGroupThread.groupThreads(with: $0.address, transaction: tx),
                isVerified: identityManager.verificationState(for: $0.address, tx: tx.asV2Read) == .verified,
                isConnection: profileManager.isUser(inProfileWhitelist: $0.address, transaction: tx),
                isBlocked: blockingManager.isAddressBlocked($0.address, transaction: tx),
                hasPendingRequest: ContactThreadFinder().contactThread(for: $0.address, tx: tx)?.hasPendingMessageRequest(transaction: tx) ?? false,
                isSystemContact: contactsManager.fetchSignalAccount(for: $0.address, transaction: tx) != nil,
                viewControllerForPresentation: viewControllerForPresentation
            )
        }
    }
}

final class NameCollisionCell: UITableViewCell {
    let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser)
    let nameLabel: UILabel = {
        let label = UILabel()

        label.textColor = Theme.primaryTextColor
        label.font = UIFont.dynamicTypeBody.semibold()
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0

        return label
    }()

    let separatorView: UIView = {
        let hairline = UIView()
        hairline.backgroundColor = Theme.cellSeparatorColor
        hairline.autoSetDimension(.height, toSize: .hairlineWidth)
        let separator = UIView()
        separator.addSubview(hairline)
        hairline.autoPinEdgesToSuperviewEdges(with: .init(top: 8, leading: 0, bottom: 0, trailing: 0))
        return separator
    }()

    private let verticalStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        return stackView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let horizontalStack = UIStackView(arrangedSubviews: [
            avatarView, verticalStack
        ])

        horizontalStack.axis = .horizontal
        horizontalStack.spacing = 16
        horizontalStack.alignment = .top

        contentView.addSubview(horizontalStack)
        horizontalStack.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func createWithModel(
        _ model: NameCollisionCellModel,
        action: NameCollisionCell.Action?
    ) -> Self {
        let cell = self.init(style: .default, reuseIdentifier: nil)
        cell.configure(model: model, action: action)
        return cell
    }

    override func prepareForReuse() {
        verticalStack.removeAllSubviews()
        avatarView.reset()
        nameLabel.text = ""
    }

    func configure(model: NameCollisionCellModel, action: NameCollisionCell.Action?) {
        verticalStack.removeAllSubviews()

        // Avatar
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(model.address)
        }

        // Name
        if model.address.isLocalAddress {
            nameLabel.text = CommonStrings.you
        } else {
            nameLabel.text = model.name
        }
        verticalStack.addArrangedSubview(nameLabel)

        let detailFont = UIFont.dynamicTypeBody2

        // Verified
        if model.isVerified {
            verticalStack.addArrangedSubview(ProfileDetailLabel.verified(font: detailFont))
        }

        // Name change
        if let profileNameChange = model.profileNameChange {
            let formatString = OWSLocalizedString(
                "NAME_COLLISION_RECENT_CHANGE_FORMAT_STRING",
                comment: "Format string describing a recent profile name change that led to a name collision. Embeds {{ %1$@ current name, which may be a profile name or an address book name }}, {{ %2$@ old profile name }}, and {{ %3$@ current profile name }}"
            )
            let string = String(
                format: formatString,
                model.shortName,
                profileNameChange.oldestProfileName,
                profileNameChange.newestProfileName
            )
            verticalStack.addArrangedSubview(ProfileDetailLabel.profile(
                displayName: string,
                font: detailFont
            ))
        }

        // Connection
        if model.isConnection {
            verticalStack.addArrangedSubview(ProfileDetailLabel.signalConnectionLink(
                font: detailFont,
                shouldDismissOnNavigation: false,
                presentEducationFrom: model.viewControllerForPresentation
            ))
        } else if model.isBlocked {
            verticalStack.addArrangedSubview(ProfileDetailLabel.blocked(
                name: model.shortName,
                font: detailFont
            ))
        } else if model.hasPendingRequest {
            verticalStack.addArrangedSubview(ProfileDetailLabel.pendingRequest(
                name: model.shortName,
                font: detailFont
            ))
        } else {
            verticalStack.addArrangedSubview(ProfileDetailLabel.noDirectChat(
                name: model.shortName,
                font: detailFont
            ))
        }

        // System contacts
        if model.isSystemContact {
            verticalStack.addArrangedSubview(ProfileDetailLabel.inSystemContacts(
                name: model.shortName,
                font: detailFont
            ))
        }

        // Phone number
        if let phoneNumber = model.address.phoneNumber {
            verticalStack.addArrangedSubview(ProfileDetailLabel.phoneNumber(
                phoneNumber,
                font: detailFont,
                presentSuccessToastFrom: model.viewControllerForPresentation
            ))
        }

        // Mutual groups
        verticalStack.addArrangedSubview(ProfileDetailLabel.mutualGroups(
            for: model.thread,
            mutualGroups: model.mutualGroups,
            font: detailFont
        ))

        separatorView.isHidden = action == nil
        verticalStack.addArrangedSubview(separatorView)

        if let action {
            verticalStack.addArrangedSubview(createButton(for: action))
        }
    }

    struct Action {
        enum Role {
            case normal
            case destructive

            var color: UIColor {
                switch self {
                case .normal:
                    return Theme.primaryTextColor
                case .destructive:
                    return .ows_accentRed
                }
            }
        }

        let title: String
        let icon: ThemeIcon
        let role: Role
        let action: () -> Void

        static func block(_ action: @escaping () -> Void) -> Action {
            Action(
                title: MessageRequestView.LocalizedStrings.block,
                icon: .chatSettingsBlock,
                role: .destructive,
                action: action
            )
        }

        static func unblock(_ action: @escaping () -> Void) -> Action {
            Action(
                title: MessageRequestView.LocalizedStrings.unblock,
                icon: .chatSettingsBlock,
                role: .normal,
                action: action
            )
        }

        static func removeFromGroup(_ action: @escaping () -> Void) -> Action {
            Action(
                title: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_REMOVE_FROM_GROUP_BUTTON",
                    comment: "Label for 'remove from group' button in conversation settings view."
                ),
                icon: .groupMemberRemoveFromGroup,
                role: .destructive,
                action: action
            )
        }

        static func updateContact(_ action: @escaping () -> Void) -> Action {
            Action(
                title: OWSLocalizedString(
                    "MESSAGE_REQUEST_NAME_COLLISON_UPDATE_CONTACT_ACTION",
                    comment: "A button that updates a known contact's information to resolve a name collision"
                ),
                icon: .profileAbout,
                role: .normal,
                action: action
            )
        }
    }

    private func createButton(for action: Action) -> UIButton {
        let button = OWSButton(
            title: action.title,
            imageName: Theme.iconName(action.icon),
            tintColor: action.role.color,
            spacing: 12,
            block: action.action
        )

        button.setTitleColor(action.role.color, for: .normal)
        button.setTitleColor(action.role.color.withAlphaComponent(0.7), for: .highlighted)

        button.titleLabel?.font = UIFont.dynamicTypeBody
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.contentHorizontalAlignment = .leading

        // By default, a button's label will grow outside of the buttons bounds
        button.titleLabel?.autoMatch(.height, to: .height, of: button, withMultiplier: 1, relation: .lessThanOrEqual)
        button.setContentHuggingHorizontalHigh()
        return button
    }
}
