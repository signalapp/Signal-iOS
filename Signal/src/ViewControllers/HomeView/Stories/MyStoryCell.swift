//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalMessaging
import SignalUI

class MyStoryCell: UITableViewCell {
    static let reuseIdentifier = "MyStoryCell"

    let titleLabel = UILabel()
    let titleChevron = UIImageView()
    let subtitleLabel = UILabel()
    let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser, badged: false, useAutolayout: true)
    let attachmentThumbnail = UIView()

    let failedIconView = UIImageView()

    let addStoryButton = OWSButton()
    let plusIcon = UIImageView()

    let contentHStackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear

        titleLabel.text = NSLocalizedString("MY_STORIES_TITLE", comment: "Title for the 'My Stories' view")

        let chevronImage = CurrentAppContext().isRTL ? UIImage(named: "chevron-left-20")! : UIImage(named: "chevron-right-20")!

        titleChevron.image = chevronImage.withRenderingMode(.alwaysTemplate)

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, titleChevron])
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 6

        failedIconView.autoSetDimension(.width, toSize: 16)
        failedIconView.contentMode = .scaleAspectFit
        failedIconView.tintColor = .ows_accentRed

        let subtitleStack = UIStackView(arrangedSubviews: [failedIconView, subtitleLabel])
        subtitleStack.axis = .horizontal
        subtitleStack.alignment = .center
        subtitleStack.spacing = 6

        let vStack = UIStackView(arrangedSubviews: [titleStack, subtitleStack])
        vStack.axis = .vertical
        vStack.alignment = .leading

        addStoryButton.addSubview(avatarView)
        avatarView.autoPinEdgesToSuperviewEdges()

        plusIcon.image = #imageLiteral(resourceName: "plus-my-story").withRenderingMode(.alwaysTemplate)
        plusIcon.tintColor = .white
        plusIcon.contentMode = .center
        plusIcon.autoSetDimensions(to: .square(26))
        plusIcon.layer.cornerRadius = 13
        plusIcon.layer.borderWidth = 3
        plusIcon.backgroundColor = .ows_accentBlue
        plusIcon.isUserInteractionEnabled = false

        addStoryButton.addSubview(plusIcon)
        plusIcon.autoPinEdge(toSuperviewEdge: .trailing, withInset: -3)
        plusIcon.autoPinEdge(toSuperviewEdge: .bottom, withInset: -3)

        contentHStackView.addArrangedSubviews([addStoryButton, vStack, .hStretchingSpacer(), attachmentThumbnail])
        contentHStackView.axis = .horizontal
        contentHStackView.alignment = .center
        contentHStackView.spacing = 16

        contentView.addSubview(contentHStackView)
        contentHStackView.autoPinEdgesToSuperviewMargins()

        attachmentThumbnail.autoSetDimensions(to: CGSize(width: 64, height: 84))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with model: MyStoryViewModel, addStoryAction: @escaping () -> Void) {
        configureSubtitle(with: model)

        titleLabel.font = .ows_dynamicTypeHeadline
        titleLabel.textColor = Theme.primaryTextColor

        titleChevron.tintColor = Theme.primaryTextColor
        titleChevron.isHiddenInStackView = model.messages.isEmpty

        plusIcon.layer.borderColor = Theme.backgroundColor.cgColor

        addStoryButton.block = addStoryAction

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(Self.tsAccountManager.localAddress!)
            config.storyState = model.messages.isEmpty ? .none : .viewed
            config.usePlaceholderImages()
        }

        attachmentThumbnail.removeAllSubviews()

        if let latestMessageAttachment = model.latestMessageAttachment {
            attachmentThumbnail.isHiddenInStackView = false

            let latestThumbnailView = StoryThumbnailView(attachment: latestMessageAttachment)
            attachmentThumbnail.addSubview(latestThumbnailView)
            latestThumbnailView.autoPinHeightToSuperview()
            latestThumbnailView.autoSetDimensions(to: CGSize(width: 56, height: 84))
            latestThumbnailView.autoPinEdge(toSuperviewEdge: .trailing)

            if let secondLatestMessageAttachment = model.secondLatestMessageAttachment {
                let secondLatestThumbnailView = StoryThumbnailView(attachment: secondLatestMessageAttachment)
                secondLatestThumbnailView.layer.cornerRadius = 6
                secondLatestThumbnailView.transform = .init(rotationAngle: (CurrentAppContext().isRTL ? 1 : -1) * 0.18168878)
                attachmentThumbnail.insertSubview(secondLatestThumbnailView, belowSubview: latestThumbnailView)
                secondLatestThumbnailView.autoPinEdge(toSuperviewEdge: .top, withInset: 4)
                secondLatestThumbnailView.autoSetDimensions(to: CGSize(width: 43, height: 64))
                secondLatestThumbnailView.autoPinEdge(toSuperviewEdge: .leading)

                let dividerView = UIView()
                dividerView.backgroundColor = Theme.backgroundColor
                dividerView.layer.cornerRadius = 12
                attachmentThumbnail.insertSubview(dividerView, belowSubview: latestThumbnailView)
                dividerView.autoSetDimensions(to: CGSize(width: 60, height: 88))
                dividerView.autoPinEdge(toSuperviewEdge: .trailing, withInset: -2)
                dividerView.autoPinEdge(toSuperviewEdge: .top, withInset: -2)
            }
        } else {
            attachmentThumbnail.isHiddenInStackView = true
        }
    }

    func configureSubtitle(with model: MyStoryViewModel) {
        subtitleLabel.font = .ows_dynamicTypeSubheadline
        subtitleLabel.textColor = Theme.isDarkThemeEnabled ? Theme.secondaryTextAndIconColor : .ows_gray45
        failedIconView.image = Theme.iconImage(.error16)

        if model.sendingCount > 0 {
            let format = NSLocalizedString("STORY_SENDING_%d", tableName: "PluralAware", comment: "Indicates that N stories are currently sending")
            subtitleLabel.text = .localizedStringWithFormat(format, model.sendingCount)
            failedIconView.isHiddenInStackView = model.failureState == .none
        } else if model.failureState != .none {
            switch model.failureState {
            case .complete:
                subtitleLabel.text = NSLocalizedString("STORY_SEND_FAILED", comment: "Text indicating that the story send has failed")
            case .partial:
                subtitleLabel.text = NSLocalizedString("STORY_SEND_PARTIALLY_FAILED", comment: "Text indicating that the story send has partially failed")
            case .none:
                owsFailDebug("Unexpected")
            }
            failedIconView.isHiddenInStackView = false
        } else if let latestMessageTimestamp = model.latestMessageTimestamp {
            subtitleLabel.text = DateUtil.formatTimestampRelatively(latestMessageTimestamp)
            failedIconView.isHiddenInStackView = true
        } else {
            subtitleLabel.text = NSLocalizedString("MY_STORY_TAP_TO_ADD", comment: "Prompt to add to your story")
            failedIconView.isHiddenInStackView = true
        }
    }
}
