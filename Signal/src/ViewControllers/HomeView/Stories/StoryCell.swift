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

    private var attachment: StoryThumbnailView.Attachment?

    func configure(with model: StoryViewModel) {
        configureSubtitle(with: model)

        switch model.context {
        case .authorUuid:
            replyImageView.image = UIImage(imageLiteralResourceName: "reply-fill-20")
        case .groupId:
            replyImageView.image = UIImage(imageLiteralResourceName: "thread-fill-20").withRenderingMode(.alwaysTemplate)
        case .privateStory:
            owsFailDebug("Unexpectedly had private story on stories list")
        case .none:
            owsFailDebug("Unexpected context")
        }

        replyImageView.isHidden = !model.hasReplies
        replyImageView.tintColor = Theme.isDarkThemeEnabled ? Theme.secondaryTextAndIconColor : .ows_gray45

        nameLabel.numberOfLines = 2
        nameLabel.font = .dynamicTypeHeadline
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.text = model.latestMessageName

        nameIconView.contentMode = .center
        nameIconView.image = Theme.iconImage(.official)
        nameIconView.isHiddenInStackView = !model.isSystemStory

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = model.latestMessageAvatarDataSource
            // We reload the row when this state changes, so don't make the avatar auto update.
            config.storyConfiguration = .fixed(model.hasUnviewedMessages ? .unviewed : .viewed)
            config.usePlaceholderImages()
        }

        attachmentThumbnail.backgroundColor = Theme.washColor
        if self.attachment != model.latestMessageAttachment {
            self.attachment = model.latestMessageAttachment
            attachmentThumbnail.removeAllSubviews()

            let storyThumbnailView = StoryThumbnailView(attachment: model.latestMessageAttachment)
            attachmentThumbnail.addSubview(storyThumbnailView)
            storyThumbnailView.autoPinEdgesToSuperviewEdges()
        }

        contentView.alpha = model.isHidden ? 0.27 : 1

        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Theme.tableCell2SelectedBackgroundColor2
        self.selectedBackgroundView = selectedBackgroundView
    }

    func configureSubtitle(with model: StoryViewModel) {
        subtitleStack.isHidden = model.isSystemStory
        subtitleLabel.font = .dynamicTypeSubheadline
        subtitleLabel.textColor = Theme.isDarkThemeEnabled ? Theme.secondaryTextAndIconColor : .ows_gray45

        switch model.latestMessageSendingState {
        case .sent:
            subtitleLabel.text = DateUtil.formatTimestampRelatively(model.latestMessageTimestamp)
            failedIconView.isHiddenInStackView = true
        case .sending, .pending:
            subtitleLabel.text = OWSLocalizedString("STORY_SENDING", comment: "Text indicating that the story is currently sending")
            failedIconView.isHiddenInStackView = true
        case .failed:
            subtitleLabel.text = model.latestMessage.hasSentToAnyRecipients
                ? OWSLocalizedString("STORY_SEND_PARTIALLY_FAILED", comment: "Text indicating that the story send has partially failed")
                : OWSLocalizedString("STORY_SEND_FAILED", comment: "Text indicating that the story send has failed")
            failedIconView.image = Theme.iconImage(.error16)
            failedIconView.isHiddenInStackView = false
        case .sent_OBSOLETE, .delivered_OBSOLETE:
            owsFailDebug("Unexpected legacy sending state")
        }
    }
}
