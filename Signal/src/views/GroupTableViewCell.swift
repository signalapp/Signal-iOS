//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalServiceKit

@objc class GroupTableViewCell: UITableViewCell {

    // MARK: - Dependencies

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    // MARK: -

    private let avatarView = AvatarImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let accessoryLabel = UILabel()

    @objc var accessoryMessage: String?

    init() {
        super.init(style: .default, reuseIdentifier: GroupTableViewCell.logTag())

        // Font config
        nameLabel.font = .ows_dynamicTypeBody
        nameLabel.textColor = Theme.primaryColor
        subtitleLabel.font = UIFont.ows_regularFont(withSize: 11.0)
        subtitleLabel.textColor = Theme.secondaryColor

        // Layout

        avatarView.autoSetDimension(.width, toSize: CGFloat(kStandardAvatarSize))
        avatarView.autoPinToSquareAspectRatio()

        let textRows = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        textRows.axis = .vertical
        textRows.alignment = .leading

        let columns = UIStackView(arrangedSubviews: [avatarView, textRows, accessoryLabel])
        columns.axis = .horizontal
        columns.alignment = .center
        columns.spacing = kContactCellAvatarTextMargin

        self.contentView.addSubview(columns)
        columns.autoPinEdgesToSuperviewMargins()

        // Accessory Label
        accessoryLabel.font = .ows_mediumFont(withSize: 13)
        accessoryLabel.textColor = Theme.middleGrayColor
        accessoryLabel.textAlignment = .right
        accessoryLabel.isHidden = true
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public func configure(thread: TSGroupThread) {
        OWSTableItem.configureCell(self)

        if let groupName = thread.groupModel.groupName, !groupName.isEmpty {
            self.nameLabel.text = groupName
        } else {
            self.nameLabel.text = MessageStrings.newGroupDefaultTitle
        }

        let groupMembers = thread.groupModel.groupMembers
        let groupMemberNames = groupMembers.map { contactsManager.displayName(for: $0) }.joined(separator: ", ")
        self.subtitleLabel.text = groupMemberNames

        self.avatarView.image = OWSAvatarBuilder.buildImage(thread: thread, diameter: kStandardAvatarSize)

        if let accessoryMessage = accessoryMessage, !accessoryMessage.isEmpty {
            accessoryLabel.text = accessoryMessage
            accessoryLabel.isHidden = false
        } else {
            accessoryLabel.isHidden = true
        }
    }

}
