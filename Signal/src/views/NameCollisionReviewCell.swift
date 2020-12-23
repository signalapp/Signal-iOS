//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct NameCollisionModel {
    let address: SignalServiceAddress
    let name: String
    let commonGroupsString: String
    let avatar: UIImage?
    let oldName: String?
    let isBlocked: Bool

    var phoneNumber: String? {
        address.phoneNumber.map {
            PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: $0)
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

    required override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let verticalStack = UIStackView(arrangedSubviews: [
            nameLabel, phoneNumberLabel, commonGroupsLabel, nameChangeSpacer, recentNameChangeLabel
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
        horizontalStack.autoPinEdge(toSuperviewSafeArea: .leading, withInset: 16)
        horizontalStack.autoPinEdge(toSuperviewSafeArea: .trailing, withInset: 16)
        horizontalStack.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
        horizontalStack.autoPinEdge(toSuperviewEdge: .bottom)

        verticalStack.autoPinEdge(.bottom, to: .bottom, of: contentView, withOffset: -12, relation: .lessThanOrEqual)
        avatarView.autoSetDimensions(to: CGSize(square: 64))

        isPairedWithActions = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func createWithModel(_ model: NameCollisionModel) -> Self {
        let cell = self.init(style: .default, reuseIdentifier: nil)
        cell.configure(model: model)
        return cell
    }

    override func prepareForReuse() {
        avatarView.image = nil
        nameLabel.text = ""
        phoneNumberLabel.text = ""
        commonGroupsLabel.text = ""
        nameChangeSpacer.isHidden = false
        recentNameChangeLabel.text = ""
    }

    func configure(model: NameCollisionModel) {
        avatarView.image = model.avatar
        nameLabel.text = model.name

        if let phoneNumber = model.phoneNumber {
            phoneNumberLabel.text = phoneNumber
        } else {
            phoneNumberLabel.isHidden = true
        }

        commonGroupsLabel.text = model.commonGroupsString

        if let oldName = model.oldName {
            nameChangeSpacer.isHidden = false
            recentNameChangeLabel.isHidden = false
            recentNameChangeLabel.text = "Recently changed their profile name from \(oldName) to Michelle!"
        } else {
            nameChangeSpacer.isHidden = true
            recentNameChangeLabel.isHidden = true
        }
    }

    lazy var avatarBottomEdgeConstraint: NSLayoutConstraint = {
        avatarView.autoPinEdge(.bottom, to: .bottom, of: contentView, withOffset: -16, relation: .lessThanOrEqual)
    }()

    // If this cell is paired with actions, we don't need to pad the avatar view
    var isPairedWithActions: Bool = false {
        didSet {
            avatarBottomEdgeConstraint.isActive = !isPairedWithActions
            separatorInset = UIEdgeInsets(top: 0, leading: isPairedWithActions ? 96 : 0, bottom: 0, trailing: 0)
        }
    }
}

class NameCollisionActionCell: UITableViewCell {
    typealias Action = (title: String, action: () -> Void)

    init(actions: [Action]) {
        owsAssertDebug(actions.count < 3, "Untested above two actions. This is likely to truncate button text")
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none

        let buttons = actions.map { (action: Action) -> UIButton in
            let button = OWSButton(title: action.title, block: action.action)
            button.setTitleColor(Theme.accentBlueColor, for: .normal)
            button.setTitleColor(Theme.accentBlueColor.withAlphaComponent(0.7), for: .highlighted)
            button.titleLabel?.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            return button
        }

        let horizontalStack = UIStackView(arrangedSubviews: buttons + [UIView()])
        horizontalStack.axis = .horizontal
        horizontalStack.distribution = .equalCentering

        contentView.addSubview(horizontalStack)
        horizontalStack.autoPinEdgesToSuperviewSafeArea(with: UIEdgeInsets(top: 8, leading: 96, bottom: 8, trailing: 0))

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
