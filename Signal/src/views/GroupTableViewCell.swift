//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalServiceKit

@objc class GroupTableViewCell: UITableViewCell {

    let TAG = "[GroupTableViewCell]"

    private let avatarView = AvatarImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()

    init() {
        super.init(style: .default, reuseIdentifier: TAG)

        self.contentView.addSubview(avatarView)

        let textContainer = UIView.container()
        textContainer.addSubview(nameLabel)
        textContainer.addSubview(subtitleLabel)
        self.contentView.addSubview(textContainer)

        // Font config
        nameLabel.font = .ows_dynamicTypeBody
        subtitleLabel.font = UIFont.ows_regularFont(withSize: 11.0)
        subtitleLabel.textColor = UIColor.ows_darkGray

        // Listen to notifications...
        // TODO avatar, group name change, group membership change, group member name change

        // Layout

        nameLabel.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets.zero, excludingEdge: .bottom)
        subtitleLabel.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets.zero, excludingEdge: .top)
        subtitleLabel.autoPinEdge(.top, to: .bottom, of: nameLabel)

        avatarView.autoPinLeadingToSuperviewMargin()
        avatarView.autoVCenterInSuperview()
        avatarView.autoSetDimension(.width, toSize: CGFloat(kContactTableViewCellAvatarSize))
        avatarView.autoPinToSquareAspectRatio()

        textContainer.autoPinEdge(.leading, to: .trailing, of: avatarView, withOffset: kContactTableViewCellAvatarTextMargin)
        textContainer.autoPinTrailingToSuperviewMargin()
        textContainer.autoVCenterInSuperview()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func configure(thread: TSGroupThread, contactsManager: OWSContactsManager) {
        if let groupName = thread.groupModel.groupName, !groupName.isEmpty {
            self.nameLabel.text = groupName
        } else {
            self.nameLabel.text = MessageStrings.newGroupDefaultTitle
        }

        let groupMemberIds: [String] = thread.groupModel.groupMemberIds
        let groupMemberNames = groupMemberIds.map { (recipientId: String) in
            contactsManager.displayName(forPhoneIdentifier: recipientId)
        }.joined(separator: ", ")
        self.subtitleLabel.text = groupMemberNames

        self.avatarView.image = OWSAvatarBuilder.buildImage(thread: thread, diameter: kContactTableViewCellAvatarSize, contactsManager: contactsManager)
    }

}
