//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

// TODO: We could theoretically replace this with QuotedMessageView, but that's very
// deeply tied into the CV rendering system and not easy to use outside of that context.
class StoryReplyPreviewView: UIView {
    init(quotedReplyModel: QuotedReplyModel, spoilerState: SpoilerRenderState) {
        super.init(frame: .zero)

        backgroundColor = .ows_gray60
        clipsToBounds = true

        let hStack = UIStackView()
        hStack.axis = .horizontal
        addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()

        let lineView = UIView()
        lineView.backgroundColor = .ows_white
        lineView.autoSetDimension(.width, toSize: 4)
        hStack.addArrangedSubview(lineView)

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .leading
        vStack.spacing = 2
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 8)
        hStack.addArrangedSubview(vStack)

        let authorLabel = UILabel()
        authorLabel.font = UIFont.dynamicTypeFootnote.semibold()
        authorLabel.textColor = Theme.darkThemePrimaryColor
        authorLabel.setCompressionResistanceHigh()

        let authorName: String
        if quotedReplyModel.isOriginalMessageAuthorLocalUser {
            authorName = CommonStrings.you
        } else {
            authorName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.contactManagerRef.displayName(for: quotedReplyModel.originalMessageAuthorAddress, tx: tx).resolvedValue()
            }
        }

        let authorText: String
        if quotedReplyModel.originalContent.isStory {
            let format = OWSLocalizedString(
                "QUOTED_REPLY_STORY_AUTHOR_INDICATOR_FORMAT",
                comment: "Message header when you are quoting a story. Embeds {{ story author name }}")
            authorText = String.localizedStringWithFormat(format, authorName)
        } else {
            authorText = authorName
        }

        authorLabel.text = authorText

        vStack.addArrangedSubview(authorLabel)

        let descriptionLabel = UILabel()
        descriptionLabel.textColor = Theme.darkThemePrimaryColor
        descriptionLabel.numberOfLines = 2
        descriptionLabel.setCompressionResistanceHigh()

        if let body = quotedReplyModel.originalMessageBody?.text.nilIfEmpty {
            descriptionLabel.font = .dynamicTypeSubheadline
            descriptionLabel.text = body
        } else {
            descriptionLabel.font = UIFont.dynamicTypeSubheadline.italic()
            descriptionLabel.text = description(forMimeType: quotedReplyModel.originalContent.attachmentMimeType)
        }

        vStack.addArrangedSubview(descriptionLabel)

        vStack.addArrangedSubview(.vStretchingSpacer())

        let trailingView: UIView
        switch quotedReplyModel.originalContent {
        case .textStory(let rendererFn):
            trailingView = rendererFn(spoilerState)
        case .attachment(_, _, let thumbnailImage), .mediaStory(_, _, let thumbnailImage):
            if let thumbnailImage {
                let imageView = UIImageView()
                imageView.contentMode = .scaleAspectFill
                imageView.image = thumbnailImage
                trailingView = imageView
            } else {
                fallthrough
            }
        default:
            owsFailDebug("Missing trailingView for quote")
            trailingView = UIView()
        }

        hStack.addArrangedSubview(trailingView)
        trailingView.autoMatch(.height, to: .width, of: trailingView, withMultiplier: 1.6)
        trailingView.autoSetDimension(.width, toSize: 40, relation: .greaterThanOrEqual)
        trailingView.setCompressionResistanceLow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath.roundedRect(bounds, sharpCorners: [.bottomLeft, .bottomRight], sharpCornerRadius: 4, wideCornerRadius: 10).cgPath
        layer.mask = maskLayer
    }

    func description(forMimeType mimeType: String?) -> String {
        if let mimeType = mimeType, MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return OWSLocalizedString(
                "QUOTED_REPLY_TYPE_VIDEO",
                comment: "Indicates this message is a quoted reply to a video file.")
        } else if let mimeType = mimeType, MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) {
            if mimeType.caseInsensitiveCompare(MimeType.imageGif.rawValue) == .orderedSame {
                return OWSLocalizedString(
                    "QUOTED_REPLY_TYPE_GIF",
                    comment: "Indicates this message is a quoted reply to animated GIF file.")
            } else {
                return OWSLocalizedString(
                    "QUOTED_REPLY_TYPE_IMAGE",
                    comment: "Indicates this message is a quoted reply to an image file.")
            }
        } else if let mimeType = mimeType, MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            return OWSLocalizedString(
                "QUOTED_REPLY_TYPE_PHOTO",
                comment: "Indicates this message is a quoted reply to a photo file.")
        } else {
            return OWSLocalizedString(
                "QUOTED_REPLY_TYPE_ATTACHMENT",
                comment: "Indicates this message is a quoted reply to an attachment of unknown type.")
        }
    }
}
