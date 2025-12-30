//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

class StoryCell: UITableViewCell {
    static let reuseIdentifier = "StoryCell"

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.font = .dynamicTypeHeadline
        label.textColor = .Signal.label
        return label
    }()

    private let nameIconView: UIImageView = {
        let imageView = UIImageView(image: Theme.iconImage(.official))
        imageView.contentMode = .center
        return imageView
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.secondaryLabel
        return label
    }()

    private let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser, useAutolayout: true)

    let attachmentThumbnail: UIView = {
        let view = UIView()
        view.autoSetDimensions(to: CGSize(width: 56, height: 84))
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }()

    private let replyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .Signal.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.autoSetDimensions(to: CGSize(square: 20))
        return imageView
    }()

    private let failedIconView: UIImageView = {
        let imageView = UIImageView(image: Theme.iconImage(.error16))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .Signal.red
        imageView.autoSetDimension(.width, toSize: 16)
        return imageView
    }()

    private lazy var subtitleStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [failedIconView, subtitleLabel])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        return stackView
    }()

    /// If set to `true` background in `selected` state would have rounded corners.
    var useSidebarAppearance = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        automaticallyUpdatesBackgroundConfiguration = false

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, nameIconView])
        nameStack.axis = .horizontal
        nameStack.alignment = .center
        nameStack.spacing = 3

        let vStack = UIStackView(arrangedSubviews: [nameStack, subtitleStack, replyImageView])
        vStack.axis = .vertical
        vStack.alignment = .leading

        let contentHStackView = UIStackView(arrangedSubviews: [avatarView, vStack, .hStretchingSpacer(), attachmentThumbnail])
        contentHStackView.axis = .horizontal
        contentHStackView.alignment = .center
        contentHStackView.spacing = 16
        contentView.addSubview(contentHStackView)
        contentHStackView.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var configuration = UIBackgroundConfiguration.clear()
        if state.isSelected || state.isHighlighted {
            configuration.backgroundColor = Theme.tableCell2SelectedBackgroundColor
            if useSidebarAppearance {
                configuration.cornerRadius = 24
            }
        } else {
            configuration.backgroundColor = .Signal.background
        }
        backgroundConfiguration = configuration
    }

    private var attachment: StoryThumbnailView.Attachment?
    private var revealedSpoilerIds: Set<StyleIdType>?

    func configure(with model: StoryViewModel, spoilerState: SpoilerRenderState) {
        configureSubtitle(with: model)

        switch model.context {
        case .authorAci:
            replyImageView.image = UIImage(imageLiteralResourceName: "reply-fill-20")
        case .groupId:
            replyImageView.image = UIImage(imageLiteralResourceName: "thread-compact-fill").withRenderingMode(.alwaysTemplate)
        case .privateStory:
            owsFailDebug("Unexpectedly had private story on stories list")
        case .none:
            owsFailDebug("Unexpected context")
        }

        replyImageView.isHidden = !model.hasReplies
        nameLabel.text = model.latestMessageName
        nameIconView.isHiddenInStackView = !model.isSystemStory

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = model.latestMessageAvatarDataSource
            // We reload the row when this state changes, so don't make the avatar auto update.
            config.storyConfiguration = .fixed(model.hasUnviewedMessages ? .unviewed : .viewed)
            config.usePlaceholderImages()
        }

        attachmentThumbnail.backgroundColor = Theme.washColor
        let revealedSpoilerIds = spoilerState.revealState.revealedSpoilerIds(interactionIdentifier: model.latestMessageIdentifier)
        if self.attachment != model.latestMessageAttachment || self.revealedSpoilerIds != revealedSpoilerIds {
            self.attachment = model.latestMessageAttachment
            self.revealedSpoilerIds = revealedSpoilerIds
            attachmentThumbnail.removeAllSubviews()

            let storyThumbnailView = StoryThumbnailView(
                attachment: model.latestMessageAttachment,
                interactionIdentifier: model.latestMessageIdentifier,
                spoilerState: spoilerState,
            )
            attachmentThumbnail.addSubview(storyThumbnailView)
            storyThumbnailView.autoPinEdgesToSuperviewEdges()
        }

        contentView.alpha = model.isHidden ? 0.27 : 1
    }

    func configureSubtitle(with model: StoryViewModel) {
        subtitleStack.isHidden = model.isSystemStory

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
            failedIconView.isHiddenInStackView = false
        case .sent_OBSOLETE, .delivered_OBSOLETE:
            owsFailDebug("Unexpected legacy sending state")
        }
    }
}
