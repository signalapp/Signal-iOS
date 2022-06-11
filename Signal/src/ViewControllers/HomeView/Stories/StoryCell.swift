//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalMessaging
import SignalUI

class StoryCell: UITableViewCell {
    static let reuseIdentifier = "StoryCell"

    let nameLabel = UILabel()
    let timestampLabel = UILabel()
    let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser, useAutolayout: true)
    let attachmentThumbnail = UIView()
    let replyImageView = UIImageView()

    let contentHStackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear

        replyImageView.autoSetDimensions(to: CGSize(square: 20))
        replyImageView.contentMode = .scaleAspectFit

        let vStack = UIStackView(arrangedSubviews: [nameLabel, timestampLabel, replyImageView])
        vStack.axis = .vertical
        vStack.alignment = .leading

        contentHStackView.addArrangedSubviews([avatarView, vStack, .hStretchingSpacer(), attachmentThumbnail])
        contentHStackView.axis = .horizontal
        contentHStackView.alignment = .center
        contentHStackView.spacing = 16

        contentView.addSubview(contentHStackView)
        contentHStackView.autoPinEdgesToSuperviewMargins()

        attachmentThumbnail.autoSetDimensions(to: CGSize(width: 56, height: 84))
        attachmentThumbnail.layer.cornerRadius = 12
        attachmentThumbnail.clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with model: StoryViewModel) {
        configureTimestamp(with: model)

        switch model.context {
        case .authorUuid:
            replyImageView.image = #imageLiteral(resourceName: "reply-solid-20").withRenderingMode(.alwaysTemplate)
        case .groupId:
            replyImageView.image = #imageLiteral(resourceName: "messages-solid-20").withRenderingMode(.alwaysTemplate)
        case .none:
            owsFailDebug("Unexpected context")
        }

        replyImageView.isHidden = !model.hasReplies
        replyImageView.tintColor = Theme.secondaryTextAndIconColor

        nameLabel.font = .ows_dynamicTypeHeadline
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.text = model.latestMessageName

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = model.latestMessageAvatarDataSource
            config.storyState = model.hasUnviewedMessages ? .unviewed : .viewed
            config.usePlaceholderImages()
        }

        attachmentThumbnail.backgroundColor = Theme.washColor
        attachmentThumbnail.removeAllSubviews()

        let storyThumbnailView = StoryThumbnailView(attachment: model.latestMessageAttachment)
        attachmentThumbnail.addSubview(storyThumbnailView)
        storyThumbnailView.autoPinEdgesToSuperviewEdges()
    }

    func configureTimestamp(with model: StoryViewModel) {
        timestampLabel.font = .ows_dynamicTypeSubheadline
        timestampLabel.textColor = Theme.secondaryTextAndIconColor
        timestampLabel.text = DateUtil.formatTimestampRelatively(model.latestMessageTimestamp)
    }
}
