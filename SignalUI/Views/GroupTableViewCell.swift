//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import UIKit

@objc
public class GroupTableViewCell: UITableViewCell {

    private let avatarView = ConversationAvatarView(sizeClass: .thirtySix, localUserDisplayMode: .asUser)
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let accessoryLabel = UILabel()

    @objc
    var accessoryMessage: String?

    public init() {
        super.init(style: .default, reuseIdentifier: GroupTableViewCell.logTag())

        // Font config
        nameLabel.font = .ows_dynamicTypeBody
        subtitleLabel.font = UIFont.ows_regularFont(withSize: 11.0)

        // Layout

        let textRows = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        textRows.axis = .vertical
        textRows.alignment = .leading

        let columns = UIStackView(arrangedSubviews: [avatarView, textRows, accessoryLabel])
        columns.axis = .horizontal
        columns.alignment = .center
        columns.spacing = ContactCellView.avatarTextHSpacing

        self.contentView.addSubview(columns)
        columns.autoPinWidthToSuperviewMargins()
        columns.autoPinHeightToSuperview(withMargin: 7)

        // Accessory Label
        accessoryLabel.font = .ows_semiboldFont(withSize: 13)
        accessoryLabel.textColor = Theme.middleGrayColor
        accessoryLabel.textAlignment = .right
        accessoryLabel.isHidden = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func configure(thread: TSGroupThread, customSubtitle: String? = nil, customTextColor: UIColor? = nil) {
        OWSTableItem.configureCell(self)

        if let groupName = thread.groupModel.groupName, !groupName.isEmpty {
            self.nameLabel.text = groupName
        } else {
            self.nameLabel.text = MessageStrings.newGroupDefaultTitle
        }

        let groupMembersCount = thread.groupModel.groupMembership.fullMembers.count
        self.subtitleLabel.text = customSubtitle ?? GroupViewUtils.formatGroupMembersLabel(memberCount: groupMembersCount)

        self.avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .thread(thread)
        }

        if let accessoryMessage = accessoryMessage, !accessoryMessage.isEmpty {
            accessoryLabel.text = accessoryMessage
            accessoryLabel.isHidden = false
        } else {
            accessoryLabel.isHidden = true
        }

        nameLabel.textColor = customTextColor ?? Theme.primaryTextColor
        subtitleLabel.textColor = customTextColor ?? Theme.secondaryTextAndIconColor
    }
}
