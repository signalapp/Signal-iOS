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
    let timestampLabel = UILabel()
    let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser, useAutolayout: true)
    let attachmentThumbnail = UIView()

    let addStoryButton = OWSButton()

    let contentHStackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear

        titleLabel.text = NSLocalizedString("MY_STORIES_TITLE", comment: "Title for the 'My Stories' view")

        let chevronImage: UIImage
        if #available(iOS 13, *) {
            chevronImage = CurrentAppContext().isRTL ? UIImage(systemName: "chevron.left")! : UIImage(systemName: "chevron.right")!
        } else {
            chevronImage = CurrentAppContext().isRTL ? UIImage(named: "chevron-left-20")! : UIImage(named: "chevron-right-20")!
        }

        titleChevron.image = chevronImage.withRenderingMode(.alwaysTemplate)

        let hStack = UIStackView(arrangedSubviews: [titleLabel, titleChevron])
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 6

        let vStack = UIStackView(arrangedSubviews: [hStack, timestampLabel])
        vStack.axis = .vertical
        vStack.alignment = .leading

        contentHStackView.addArrangedSubviews([avatarView, vStack, .hStretchingSpacer(), attachmentThumbnail])
        contentHStackView.axis = .horizontal
        contentHStackView.alignment = .center
        contentHStackView.spacing = 16

        contentView.addSubview(contentHStackView)
        contentHStackView.autoPinEdgesToSuperviewMargins()

        attachmentThumbnail.autoSetDimensions(to: CGSize(width: 64, height: 84))

        addStoryButton.setImage(imageName: "plus-24")
        addStoryButton.layer.cornerRadius = 12
        addStoryButton.clipsToBounds = true
        addStoryButton.autoSetDimensions(to: CGSize(width: 56, height: 84))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with model: MyStoryViewModel, addStoryAction: @escaping () -> Void) {
        configureTimestamp(with: model)

        titleLabel.font = .ows_dynamicTypeHeadline
        titleLabel.textColor = Theme.primaryTextColor
        titleChevron.tintColor = Theme.primaryTextColor

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(Self.tsAccountManager.localAddress!)
            config.storyState = .viewed
            config.usePlaceholderImages()
        }

        attachmentThumbnail.removeAllSubviews()

        if let latestMessageAttachment = model.latestMessageAttachment {
            let latestThumbnailView = StoryThumbnailView(attachment: latestMessageAttachment)
            attachmentThumbnail.addSubview(latestThumbnailView)
            latestThumbnailView.autoPinHeightToSuperview()
            latestThumbnailView.autoSetDimensions(to: CGSize(width: 56, height: 84))
            latestThumbnailView.autoPinEdge(toSuperviewEdge: .trailing)

            if let secondLatestMessageAttachment = model.secondLatestMessageAttachment {
                let secondLatestThumbnailView = StoryThumbnailView(attachment: secondLatestMessageAttachment)
                secondLatestThumbnailView.layer.cornerRadius = 6
                secondLatestThumbnailView.transform = .init(rotationAngle: -0.18168878)
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
            addStoryButton.block = addStoryAction
            addStoryButton.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray10
            addStoryButton.tintColor = Theme.primaryTextColor
            attachmentThumbnail.addSubview(addStoryButton)
            addStoryButton.autoPinHeightToSuperview()
            addStoryButton.autoPinEdge(toSuperviewEdge: .trailing)
        }
    }

    func configureTimestamp(with model: MyStoryViewModel) {
        timestampLabel.font = .ows_dynamicTypeSubheadline
        timestampLabel.textColor = Theme.secondaryTextAndIconColor
        if let latestMessageTimestamp = model.latestMessageTimestamp {
            timestampLabel.text = DateUtil.formatTimestampRelatively(latestMessageTimestamp)
        } else {
            timestampLabel.text = nil
        }
    }
}
