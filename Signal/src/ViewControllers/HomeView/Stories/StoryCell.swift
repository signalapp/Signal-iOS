//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalMessaging

class StoryCell: UITableViewCell {
    static let reuseIdentifier = "StoryCell"

    let nameLabel = UILabel()
    let timestampLabel = UILabel()
    let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .noteToSelf, useAutolayout: true)
    let attachmentThumbnail = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let vStack = UIStackView(arrangedSubviews: [nameLabel, timestampLabel])
        vStack.axis = .vertical

        let hStack = UIStackView(arrangedSubviews: [avatarView, vStack, .hStretchingSpacer(), attachmentThumbnail])
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 16

        contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()

        attachmentThumbnail.autoSetDimensions(to: CGSize(width: 56, height: 84))
        attachmentThumbnail.layer.cornerRadius = 12
        attachmentThumbnail.clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with model: IncomingStoryViewModel) {
        nameLabel.font = .ows_dynamicTypeHeadline
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.text = model.latestRecordName

        timestampLabel.font = .ows_dynamicTypeSubheadline
        timestampLabel.textColor = Theme.secondaryTextAndIconColor
        timestampLabel.text = DateUtil.formatTimestampShort(model.latestRecordTimestamp)
        // TODO: Live update timestamp

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = model.latestRecordAvatarDataSource
            config.usePlaceholderImages()
        }

        attachmentThumbnail.backgroundColor = Theme.washColor
        attachmentThumbnail.removeAllSubviews()

        switch model.latestRecordAttachment {
        case .file(let attachment):
            // TODO: Downloading state
            guard let attachment = attachment as? TSAttachmentStream else { break }
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            attachmentThumbnail.addSubview(imageView)
            imageView.autoPinEdgesToSuperviewEdges()
            attachment.thumbnailImageSmall {
                imageView.image = $0
            } failure: {
                owsFailDebug("Failed to generate thumbnail")
            }
        case .text(let attachment):
            // TODO: Render text attachments
            break
        case .missing:
            // TODO: error state
            break
        }
    }
}
