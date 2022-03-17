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
    let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser, useAutolayout: true)
    let attachmentThumbnail = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear

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
        configureTimestamp(with: model)

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

        switch model.latestMessageAttachment {
        case .file(let attachment):
            if let pointer = attachment as? TSAttachmentPointer {
                let pointerView = UIView()

                if let blurHashImageView = buildBlurHashImageViewIfAvailable(pointer: pointer) {
                    pointerView.addSubview(blurHashImageView)
                    blurHashImageView.autoPinEdgesToSuperviewEdges()
                }

                let downloadStateView = buildDownloadStateView(for: pointer)
                pointerView.addSubview(downloadStateView)
                downloadStateView.autoPinEdgesToSuperviewEdges()

                attachmentThumbnail.addSubview(pointerView)
                pointerView.autoPinEdgesToSuperviewEdges()
            } else if let stream = attachment as? TSAttachmentStream {
                let backgroundImageView = buildBackgroundImageView(stream: stream)
                attachmentThumbnail.addSubview(backgroundImageView)
                backgroundImageView.autoPinEdgesToSuperviewEdges()
                let imageView = buildThumbnailImageView(stream: stream)
                attachmentThumbnail.addSubview(imageView)
                imageView.autoPinEdgesToSuperviewEdges()
            } else {
                owsFailDebug("Unexpected attachment type \(type(of: attachment))")
            }
        case .text(let attachment):
            let textView = TextAttachmentView(attachment: attachment)
            // We render the textView at a large 3:2 size (matching the aspect of
            // the thumbnail container), so the fonts and gradients all render properly
            // for the preview. We then scale it down to render a "thumbnail" view.
            let textViewRenderSize = CGSize(width: 375, height: 562.5)
            textView.frame = CGRect(origin: .zero, size: textViewRenderSize)

            let layerView = OWSLayerView(frame: .zero) { view in
                textView.transform = .scale(view.width / textViewRenderSize.width)
                textView.center = view.center
            }
            layerView.addSubview(textView)

            attachmentThumbnail.addSubview(layerView)
            layerView.autoPinEdgesToSuperviewEdges()
        case .missing:
            // TODO: error state
            break
        }
    }

    private func buildBackgroundImageView(stream: TSAttachmentStream) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        stream.thumbnailImageSmall {
            imageView.image = $0
        } failure: {
            owsFailDebug("Failed to generate thumbnail")
        }

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        imageView.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        return imageView
    }

    private func buildThumbnailImageView(stream: TSAttachmentStream) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true

        stream.thumbnailImageSmall {
            imageView.image = $0
        } failure: {
            owsFailDebug("Failed to generate thumbnail")
        }

        return imageView
    }

    private func buildBlurHashImageViewIfAvailable(pointer: TSAttachmentPointer) -> UIView? {
        guard let blurHash = pointer.blurHash, let blurHashImage = BlurHash.image(for: blurHash) else {
            return nil
        }
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true
        imageView.image = blurHashImage
        return imageView
    }

    private static let mediaCache = CVMediaCache()
    private func buildDownloadStateView(for pointer: TSAttachmentPointer) -> UIView {
        let view = UIView()

        let progressView = CVAttachmentProgressView(
            direction: .download(attachmentPointer: pointer),
            style: .withCircle,
            isDarkThemeEnabled: true,
            mediaCache: Self.mediaCache
        )
        view.addSubview(progressView)
        progressView.autoSetDimensions(to: progressView.layoutSize)
        progressView.autoCenterInSuperview()

        return view
    }

    func configureTimestamp(with model: IncomingStoryViewModel) {
        timestampLabel.font = .ows_dynamicTypeSubheadline
        timestampLabel.textColor = Theme.secondaryTextAndIconColor
        timestampLabel.text = DateUtil.formatTimestampShort(model.latestMessageTimestamp)
    }
}
