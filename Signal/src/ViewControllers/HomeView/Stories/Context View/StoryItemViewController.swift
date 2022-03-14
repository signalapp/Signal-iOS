//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import YYImage
import UIKit
import SignalUI

class StoryItemViewController: OWSViewController {
    let item: StoryItem
    init(item: StoryItem) {
        self.item = item
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
        timestampLabel.text = DateUtil.formatTimestampShort(item.record.timestamp)
    }

    func startAttachmentDownloadIfNecessary() -> Bool {
        guard case .pointer(let pointer) = item.attachment, ![.enqueued, .downloading].contains(pointer.state) else { return false }
        attachmentDownloads.enqueueDownloadOfAttachments(
            forStoryMessageId: item.record.id!,
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
        if let videoPlayer = videoPlayer, let asset = videoPlayer.avPlayer.currentItem?.asset {
            return CMTimeGetSeconds(asset.duration)
        } else {
            return 5
        }
    }

    var elapsedTime: CFTimeInterval? {
        guard let currentTime = videoPlayer?.avPlayer.currentTime() else { return nil }
        return CMTimeGetSeconds(currentTime)
    }

    private lazy var iPadLandscapeConstraints = [
        mediaViewContainer.autoMatch(
            .height,
            to: .height,
            of: view,
            withMultiplier: 0.75,
            relation: .lessThanOrEqual
        )
    ]
    private lazy var iPadPortraitConstraints = [
        mediaViewContainer.autoMatch(
            .height,
            to: .height,
            of: view,
            withMultiplier: 0.65,
            relation: .lessThanOrEqual
        )
    ]

    private let mediaViewContainer = UIView()

    private lazy var iPhoneConstraints = [
        mediaViewContainer.autoPinEdge(toSuperviewEdge: .top),
        mediaViewContainer.autoPinEdge(toSuperviewEdge: .leading),
        mediaViewContainer.autoPinEdge(toSuperviewEdge: .trailing)
    ]

    private lazy var iPadConstraints: [NSLayoutConstraint] = {
        var constraints = mediaViewContainer.autoCenterInSuperview()

        // Prefer to be as big as possible.
        let heightConstraint = mediaViewContainer.autoMatch(.height, to: .height, of: view)
        heightConstraint.priority = .defaultHigh
        constraints.append(heightConstraint)

        let widthConstraint = mediaViewContainer.autoMatch(.width, to: .width, of: view)
        widthConstraint.priority = .defaultHigh
        constraints.append(widthConstraint)

        return constraints
    }()

    private lazy var topGradientView: UIView = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0.5).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        let view = OWSLayerView(frame: .zero) { view in
            gradientLayer.frame = view.bounds
        }
        view.layer.addSublayer(gradientLayer)
        return view
    }()

    private lazy var bottomGradientView: UIView = {
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

    override func viewDidLoad() {
        super.viewDidLoad()

        mediaViewContainer.backgroundColor = .black
        mediaViewContainer.autoPin(toAspectRatio: 9/16)
        view.addSubview(mediaViewContainer)

        updateMediaView()

        if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
            mediaViewContainer.layer.cornerRadius = 18
            mediaViewContainer.clipsToBounds = true
        } else {
            mediaViewContainer.autoPinEdge(toSuperviewEdge: .bottom)
        }

        mediaViewContainer.addSubview(topGradientView)
        topGradientView.autoPinWidthToSuperview()
        topGradientView.autoPinEdge(toSuperviewEdge: .top)
        topGradientView.autoMatch(.height, to: .height, of: mediaViewContainer, withMultiplier: 0.4)

        mediaViewContainer.addSubview(bottomGradientView)
        bottomGradientView.autoPinWidthToSuperview()
        bottomGradientView.autoPinEdge(toSuperviewEdge: .bottom)
        bottomGradientView.autoMatch(.height, to: .height, of: mediaViewContainer, withMultiplier: 0.4)

        createAuthorRow()

        applyConstraints()
    }

    private func applyConstraints(newSize: CGSize = CurrentAppContext().frame.size) {
        NSLayoutConstraint.deactivate(iPhoneConstraints)
        NSLayoutConstraint.deactivate(iPadConstraints)
        NSLayoutConstraint.deactivate(iPadPortraitConstraints)
        NSLayoutConstraint.deactivate(iPadLandscapeConstraints)

        if UIDevice.current.isIPad {
            NSLayoutConstraint.activate(iPadConstraints)
            if newSize.width > newSize.height {
                NSLayoutConstraint.activate(iPadLandscapeConstraints)
            } else {
                NSLayoutConstraint.activate(iPadPortraitConstraints)
            }
        } else {
            NSLayoutConstraint.activate(iPhoneConstraints)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.applyConstraints(newSize: size)
        } completion: { _ in
            self.applyConstraints()
        }
    }

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

        mediaViewContainer.addSubview(stackView)
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
            config.dataSource = .address(item.record.authorAddress)
        }

        switch item.record.context {
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
            switch item.record.context {
            case .groupId(let groupId):
                let groupName: String = {
                    guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                        owsFailDebug("Missing group thread for group story")
                        return TSGroupThread.defaultGroupName
                    }
                    return groupThread.groupNameOrDefault
                }()

                let authorShortName = Self.contactsManager.shortDisplayName(
                    for: item.record.authorAddress,
                    transaction: transaction
                )
                let nameFormat = NSLocalizedString(
                    "GROUP_STORY_NAME_FORMAT",
                    comment: "Name for a group story on the stories list. Embeds {author's name}, {group name}")
                return String(format: nameFormat, authorShortName, groupName)
            default:
                return Self.contactsManager.displayName(
                    for: item.record.authorAddress,
                    transaction: transaction
                )
            }
        }()
        return label
    }

    private var mediaView: UIView?
    private func updateMediaView() {
        mediaView?.removeFromSuperview()

        let mediaView = buildMediaView()
        self.mediaView = mediaView
        mediaViewContainer.insertSubview(mediaView, at: 0)
        mediaView.autoPinEdgesToSuperviewEdges()
    }

    private func buildMediaView() -> UIView {
        // TODO: Talk to design about how we handle things that are not 9:16.
        // Do we letter box? What does the letterboxing look like?
        let contentMode: UIView.ContentMode = .scaleAspectFill

        switch item.attachment {
        case .stream(let stream):
            guard let originalMediaUrl = stream.originalMediaURL else {
                owsFailDebug("Missing media for attachment stream")
                return buildContentUnavailableView()
            }

            if stream.isVideo {
                return buildVideoView(originalMediaUrl: originalMediaUrl, contentMode: contentMode)
            } else if stream.shouldBeRenderedByYY {
                return buildYYImageView(originalMediaUrl: originalMediaUrl, contentMode: contentMode)
            } else if stream.isImage {
                return buildImageView(originalMediaUrl: originalMediaUrl, contentMode: contentMode)
            } else {
                owsFailDebug("Unexpected content type.")
                return buildContentUnavailableView()
            }
        case .pointer(let pointer):
            let container = UIView()

            if let blurHashImageView = buildBlurHashImageViewIfAvailable(pointer: pointer, contentMode: contentMode) {
                container.addSubview(blurHashImageView)
                blurHashImageView.autoPinEdgesToSuperviewEdges()
            }

            let view = buildDownloadStateView(for: pointer)
            container.addSubview(view)
            view.autoPinEdgesToSuperviewEdges()

            return container
        case .text(let text):
            // TODO:
            return UIView()
        }
    }

    private var videoPlayer: OWSVideoPlayer?
    private func buildVideoView(originalMediaUrl: URL, contentMode: UIView.ContentMode) -> UIView {
        let player = OWSVideoPlayer(url: originalMediaUrl, shouldLoop: false)
        self.videoPlayer = player

        let playerView = VideoPlayerView()
        playerView.contentMode = contentMode
        playerView.videoPlayer = player
        player.play()

        return playerView
    }

    private func buildYYImageView(originalMediaUrl: URL, contentMode: UIView.ContentMode) -> UIView {
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
        animatedImageView.contentMode = contentMode
        animatedImageView.layer.minificationFilter = .trilinear
        animatedImageView.layer.magnificationFilter = .trilinear
        animatedImageView.layer.allowsEdgeAntialiasing = true
        animatedImageView.image = image
        return animatedImageView
    }

    private func buildImageView(originalMediaUrl: URL, contentMode: UIView.ContentMode) -> UIView {
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
        imageView.contentMode = contentMode
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true
        imageView.image = image
        return imageView
    }

    private func buildBlurHashImageViewIfAvailable(pointer: TSAttachmentPointer, contentMode: UIView.ContentMode) -> UIView? {
        guard let blurHash = pointer.blurHash, let blurHashImage = BlurHash.image(for: blurHash) else {
            return nil
        }
        let imageView = UIImageView()
        imageView.contentMode = contentMode
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

    private func buildContentUnavailableView() -> UIView {
        // TODO: Error state
        return UIView()
    }
}

class StoryItem: NSObject {
    let record: StoryMessageRecord
    enum Attachment {
        case pointer(TSAttachmentPointer)
        case stream(TSAttachmentStream)
        case text(TextAttachment)
    }
    var attachment: Attachment

    init(record: StoryMessageRecord, attachment: Attachment) {
        self.record = record
        self.attachment = attachment
    }
}
