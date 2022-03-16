//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import YYImage
import UIKit
import SignalUI
import SafariServices

class StoryItemMediaView: UIView {
    let item: StoryItem
    init(item: StoryItem) {
        self.item = item

        super.init(frame: .zero)

        autoPin(toAspectRatio: 9/16)

        updateMediaView()

        if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
            layer.cornerRadius = 18
            clipsToBounds = true
        }

        addSubview(gradientProtectionView)
        gradientProtectionView.autoPinWidthToSuperview()
        gradientProtectionView.autoPinEdge(toSuperviewEdge: .bottom)
        gradientProtectionView.autoMatch(.height, to: .height, of: self, withMultiplier: 0.4)

        createAuthorRow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        videoPlayer?.seek(to: .zero)
        videoPlayer?.play()
        updateTimestampText()
    }

    func pause() {
        videoPlayer?.pause()
    }

    func play() {
        videoPlayer?.play()
    }

    func updateTimestampText() {
        timestampLabel.text = DateUtil.formatTimestampShort(item.message.timestamp)
    }

    func willHandleTapGesture(_ gesture: UITapGestureRecognizer) -> Bool {
        if startAttachmentDownloadIfNecessary() { return true }

        if let textAttachmentView = mediaView as? TextAttachmentView {
            return textAttachmentView.willHandleTapGesture(gesture)
        }

        return false
    }

    private func startAttachmentDownloadIfNecessary() -> Bool {
        guard case .pointer(let pointer) = item.attachment, ![.enqueued, .downloading].contains(pointer.state) else { return false }
        attachmentDownloads.enqueueDownloadOfAttachments(
            forStoryMessageId: item.message.uniqueId,
            attachmentGroup: .allAttachmentsIncoming,
            downloadBehavior: .bypassAll,
            touchMessageImmediately: true) { [weak self] _ in
                Logger.info("Successfully re-downloaded attachment.")
                DispatchQueue.main.async { self?.updateMediaView() }
            } failure: { [weak self] error in
                Logger.warn("Failed to redownload attachment with error: \(error)")
                DispatchQueue.main.async { self?.updateMediaView() }
            }
        return true
    }

    var isDownloading: Bool {
        guard case .pointer(let pointer) = item.attachment else { return false }
        return [.enqueued, .downloading].contains(pointer.state)
    }

    var duration: CFTimeInterval {
        if let asset = videoPlayer?.avPlayer.currentItem?.asset {
            return CMTimeGetSeconds(asset.duration)
        } else {
            return 5
        }
    }

    var elapsedTime: CFTimeInterval? {
        guard let currentTime = videoPlayer?.avPlayer.currentTime() else { return nil }
        return CMTimeGetSeconds(currentTime)
    }

    private lazy var gradientProtectionView: UIView = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.5).cgColor
        ]
        let view = OWSLayerView(frame: .zero) { view in
            gradientLayer.frame = view.bounds
        }
        view.layer.addSublayer(gradientLayer)
        return view
    }()

    private lazy var timestampLabel = UILabel()
    private func createAuthorRow() {
        let (avatarView, nameLabel) = databaseStorage.read { (
            buildAvatarView(transaction: $0),
            buildNameLabel(transaction: $0)
        ) }

        let stackView = UIStackView(arrangedSubviews: [
            avatarView,
            .spacer(withWidth: 12),
            nameLabel,
            .spacer(withWidth: 8),
            timestampLabel,
            .hStretchingSpacer()
        ])
        stackView.axis = .horizontal
        stackView.alignment = .center

        timestampLabel.font = .ows_dynamicTypeFootnote
        timestampLabel.textColor = Theme.darkThemeSecondaryTextAndIconColor
        updateTimestampText()

        addSubview(stackView)
        stackView.autoPinWidthToSuperview(withMargin: OWSTableViewController2.defaultHOuterMargin)
        stackView.autoPinEdge(toSuperviewEdge: .bottom, withInset: OWSTableViewController2.defaultHOuterMargin + 16)
    }

    private func buildAvatarView(transaction: SDSAnyReadTransaction) -> UIView {
        let authorAvatarView = ConversationAvatarView(
            sizeClass: .twentyEight,
            localUserDisplayMode: .asLocalUser,
            badged: false,
            shape: .circular,
            useAutolayout: true
        )
        authorAvatarView.update(transaction) { config in
            config.dataSource = .address(item.message.authorAddress)
        }

        switch item.message.context {
        case .groupId(let groupId):
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                owsFailDebug("Unexpectedly missing group thread")
                return authorAvatarView
            }

            let groupAvatarView = ConversationAvatarView(
                sizeClass: .twentyEight,
                localUserDisplayMode: .asLocalUser,
                badged: false,
                shape: .circular,
                useAutolayout: true
            )
            groupAvatarView.update(transaction) { config in
                config.dataSource = .thread(groupThread)
            }

            let avatarContainer = UIView()
            avatarContainer.addSubview(authorAvatarView)
            authorAvatarView.autoPinHeightToSuperview()
            authorAvatarView.autoPinEdge(toSuperviewEdge: .leading)

            avatarContainer.addSubview(groupAvatarView)
            groupAvatarView.autoPinHeightToSuperview()
            groupAvatarView.autoPinEdge(toSuperviewEdge: .trailing)
            groupAvatarView.autoPinEdge(.leading, to: .trailing, of: authorAvatarView, withOffset: -4)

            return avatarContainer
        case .authorUuid, .none:
            return authorAvatarView
        }
    }

    private func buildNameLabel(transaction: SDSAnyReadTransaction) -> UIView {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = UIFont.ows_dynamicTypeSubheadline.ows_semibold
        label.text = {
            switch item.message.context {
            case .groupId(let groupId):
                let groupName: String = {
                    guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                        owsFailDebug("Missing group thread for group story")
                        return TSGroupThread.defaultGroupName
                    }
                    return groupThread.groupNameOrDefault
                }()

                let authorShortName = Self.contactsManager.shortDisplayName(
                    for: item.message.authorAddress,
                    transaction: transaction
                )
                let nameFormat = NSLocalizedString(
                    "GROUP_STORY_NAME_FORMAT",
                    comment: "Name for a group story on the stories list. Embeds {author's name}, {group name}")
                return String(format: nameFormat, authorShortName, groupName)
            default:
                return Self.contactsManager.displayName(
                    for: item.message.authorAddress,
                    transaction: transaction
                )
            }
        }()
        return label
    }

    private weak var mediaView: UIView?
    private func updateMediaView() {
        mediaView?.removeFromSuperview()

        let mediaView = buildMediaView()
        self.mediaView = mediaView
        insertSubview(mediaView, at: 0)
        mediaView.autoPinEdgesToSuperviewEdges()
    }

    private func buildMediaView() -> UIView {
        switch item.attachment {
        case .stream(let stream):
            let container = UIView()

            guard let originalMediaUrl = stream.originalMediaURL else {
                owsFailDebug("Missing media for attachment stream")
                return buildContentUnavailableView()
            }

            guard let thumbnailImage = stream.thumbnailImageSmallSync() else {
                owsFailDebug("Failed to generate thumbnail for attachment stream")
                return buildContentUnavailableView()
            }

            let backgroundImageView = buildBackgroundImageView(thumbnailImage: thumbnailImage)
            container.addSubview(backgroundImageView)
            backgroundImageView.autoPinEdgesToSuperviewEdges()

            if stream.isVideo {
                let videoView = buildVideoView(originalMediaUrl: originalMediaUrl)
                container.addSubview(videoView)
                videoView.autoPinEdgesToSuperviewEdges()
            } else if stream.shouldBeRenderedByYY {
                let yyImageView = buildYYImageView(originalMediaUrl: originalMediaUrl)
                container.addSubview(yyImageView)
                yyImageView.autoPinEdgesToSuperviewEdges()
            } else if stream.isImage {
                let imageView = buildImageView(originalMediaUrl: originalMediaUrl)
                container.addSubview(imageView)
                imageView.autoPinEdgesToSuperviewEdges()
            } else {
                owsFailDebug("Unexpected content type.")
                return buildContentUnavailableView()
            }

            return container
        case .pointer(let pointer):
            let container = UIView()

            if let blurHashImageView = buildBlurHashImageViewIfAvailable(pointer: pointer) {
                container.addSubview(blurHashImageView)
                blurHashImageView.autoPinEdgesToSuperviewEdges()
            }

            let view = buildDownloadStateView(for: pointer)
            container.addSubview(view)
            view.autoPinEdgesToSuperviewEdges()

            return container
        case .text(let text):
            return TextAttachmentView(attachment: text)
        }
    }

    private var videoPlayer: OWSVideoPlayer?
    private func buildVideoView(originalMediaUrl: URL) -> UIView {
        let player = OWSVideoPlayer(url: originalMediaUrl, shouldLoop: false)
        self.videoPlayer = player

        let playerView = VideoPlayerView()
        playerView.contentMode = .scaleAspectFit
        playerView.videoPlayer = player
        player.play()

        return playerView
    }

    private func buildYYImageView(originalMediaUrl: URL) -> UIView {
        guard let image = YYImage(contentsOfFile: originalMediaUrl.path) else {
            owsFailDebug("Could not load attachment.")
            return buildContentUnavailableView()
        }
        guard image.size.width > 0,
            image.size.height > 0 else {
                owsFailDebug("Attachment has invalid size.")
                return buildContentUnavailableView()
        }
        let animatedImageView = YYAnimatedImageView()
        animatedImageView.contentMode = .scaleAspectFit
        animatedImageView.layer.minificationFilter = .trilinear
        animatedImageView.layer.magnificationFilter = .trilinear
        animatedImageView.layer.allowsEdgeAntialiasing = true
        animatedImageView.image = image
        return animatedImageView
    }

    private func buildImageView(originalMediaUrl: URL) -> UIView {
        guard let image = UIImage(contentsOfFile: originalMediaUrl.path) else {
            owsFailDebug("Could not load attachment.")
            return buildContentUnavailableView()
        }
        guard image.size.width > 0,
            image.size.height > 0 else {
                owsFailDebug("Attachment has invalid size.")
                return buildContentUnavailableView()
        }

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true
        imageView.image = image
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

    private func buildBackgroundImageView(thumbnailImage: UIImage) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.image = thumbnailImage

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        imageView.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

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

    private func buildContentUnavailableView() -> UIView {
        // TODO: Error state
        return UIView()
    }
}

class StoryItem: NSObject {
    let message: StoryMessage
    enum Attachment {
        case pointer(TSAttachmentPointer)
        case stream(TSAttachmentStream)
        case text(TextAttachment)
    }
    var attachment: Attachment

    init(message: StoryMessage, attachment: Attachment) {
        self.message = message
        self.attachment = attachment
    }
}
