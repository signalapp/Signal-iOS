//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging
import SignalUI

class StoryCell: UITableViewCell {
    static let reuseIdentifier = "StoryCell"

    let nameLabel = UILabel()
    let nameIconView = UIImageView()
    let subtitleLabel = UILabel()
    let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser, useAutolayout: true)
    let attachmentThumbnail = UIView()
    let replyImageView = UIImageView()

    let failedIconView = UIImageView()

    let contentHStackView = UIStackView()
    let subtitleStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear

        replyImageView.autoSetDimensions(to: CGSize(square: 20))
        replyImageView.contentMode = .scaleAspectFit

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, nameIconView])
        nameStack.axis = .horizontal
        nameStack.alignment = .center
        nameStack.spacing = 3

        failedIconView.autoSetDimension(.width, toSize: 16)
        failedIconView.contentMode = .scaleAspectFit
        failedIconView.tintColor = .ows_accentRed

        subtitleStack.addArrangedSubviews([failedIconView, subtitleLabel])
        subtitleStack.axis = .horizontal
        subtitleStack.alignment = .center
        subtitleStack.spacing = 6

        let vStack = UIStackView(arrangedSubviews: [nameStack, subtitleStack, replyImageView])
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
        configureSubtitle(with: model)

        switch model.context {
        case .authorUuid:
            replyImageView.image = #imageLiteral(resourceName: "reply-solid-20").withRenderingMode(.alwaysTemplate)
        case .groupId:
            replyImageView.image = #imageLiteral(resourceName: "messages-solid-20").withRenderingMode(.alwaysTemplate)
        case .privateStory:
            owsFailDebug("Unexpectedly had private story on stories list")
        case .none:
            owsFailDebug("Unexpected context")
        }

        replyImageView.isHidden = !model.hasReplies
        replyImageView.tintColor = Theme.isDarkThemeEnabled ? Theme.secondaryTextAndIconColor : .ows_gray45

        nameLabel.numberOfLines = 2
        nameLabel.font = .ows_dynamicTypeHeadline
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.text = model.latestMessageName

        nameIconView.contentMode = .center
        nameIconView.image = UIImage(named: "official-checkmark-20")
        nameIconView.isHiddenInStackView = !model.isSystemStory

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

        contentView.alpha = model.isHidden ? 0.27 : 1
    }

    func configureSubtitle(with model: StoryViewModel) {
        subtitleStack.isHidden = model.isSystemStory
        subtitleLabel.font = .ows_dynamicTypeSubheadline
        subtitleLabel.textColor = Theme.isDarkThemeEnabled ? Theme.secondaryTextAndIconColor : .ows_gray45

        switch model.latestMessageSendingState {
        case .sent:
            subtitleLabel.text = DateUtil.formatTimestampRelatively(model.latestMessageTimestamp)
            failedIconView.isHiddenInStackView = true
        case .sending, .pending:
            subtitleLabel.text = NSLocalizedString("STORY_SENDING", comment: "Text indicating that the story is currently sending")
            failedIconView.isHiddenInStackView = true
        case .failed:
            subtitleLabel.text = model.latestMessage.hasSentToAnyRecipients
                ? NSLocalizedString("STORY_SEND_PARTIALLY_FAILED", comment: "Text indicating that the story send has partially failed")
                : NSLocalizedString("STORY_SEND_FAILED", comment: "Text indicating that the story send has failed")
            failedIconView.image = Theme.iconImage(.error16)
            failedIconView.isHiddenInStackView = false
        case .sent_OBSOLETE, .delivered_OBSOLETE:
            owsFailDebug("Unexpected legacy sending state")
        }
    }
}
