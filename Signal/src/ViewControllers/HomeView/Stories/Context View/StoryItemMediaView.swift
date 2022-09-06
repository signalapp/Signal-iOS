//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import YYImage
import UIKit
import SignalUI
import SafariServices
import CoreMedia

protocol StoryItemMediaViewDelegate: AnyObject {
    func storyItemMediaViewWantsToPause(_ storyItemMediaView: StoryItemMediaView)
    func storyItemMediaViewWantsToPlay(_ storyItemMediaView: StoryItemMediaView)

    func storyItemMediaViewShouldBeMuted(_ storyItemMediaView: StoryItemMediaView) -> Bool
}

class StoryItemMediaView: UIView {
    weak var delegate: StoryItemMediaViewDelegate?
    let item: StoryItem

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

    private let bottomContentVStack = UIStackView()

    init(item: StoryItem, delegate: StoryItemMediaViewDelegate) {
        self.item = item
        self.delegate = delegate

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

        bottomContentVStack.axis = .vertical
        bottomContentVStack.spacing = 24
        addSubview(bottomContentVStack)

        bottomContentVStack.autoPinWidthToSuperview(withMargin: OWSTableViewController2.defaultHOuterMargin)

        if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
            // iPhone with notch or iPad (views/replies rendered below media, media is in a card)
            bottomContentVStack.autoPinEdge(toSuperviewEdge: .bottom, withInset: OWSTableViewController2.defaultHOuterMargin + 16)
        } else {
            // iPhone with home button (views/replies rendered on top of media, media is fullscreen)
            bottomContentVStack.autoPinEdge(toSuperviewEdge: .bottom, withInset: 80)
        }

        bottomContentVStack.autoPinEdge(toSuperviewEdge: .top, withInset: OWSTableViewController2.defaultHOuterMargin)

        bottomContentVStack.addArrangedSubview(.vStretchingSpacer())

        createCaptionIfNecessary()
        createAuthorRow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        videoPlayerLoopCount = 0
        videoPlayer?.seek(to: .zero)
        videoPlayer?.play()
        updateTimestampText()
        bottomContentVStack.alpha = 1
        gradientProtectionView.alpha = 1
    }

    func updateTimestampText() {
        timestampLabel.isHidden = item.message.authorAddress.isSystemStoryAddress
        timestampLabel.text = DateUtil.formatTimestampRelatively(item.message.timestamp)
    }

    func willHandleTapGesture(_ gesture: UITapGestureRecognizer) -> Bool {
        if startAttachmentDownloadIfNecessary(gesture) { return true }
        if toggleCaptionExpansionIfNecessary(gesture) { return true }

        if let textAttachmentView = mediaView as? TextAttachmentView {
            let didHandle = textAttachmentView.willHandleTapGesture(gesture)
            if didHandle {
                if textAttachmentView.isPresentingLinkTooltip {
                    // If we presented a link, pause playback
                    delegate?.storyItemMediaViewWantsToPause(self)
                } else {
                    // If we dismissed a link, resume playback
                    delegate?.storyItemMediaViewWantsToPlay(self)
                }
            }
            return didHandle
        }

        return false
    }

    // MARK: - Playback

    func pause(hideChrome: Bool = false, animateAlongside: (() -> Void)? = nil) {
        videoPlayer?.pause()

        if hideChrome {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                self.bottomContentVStack.alpha = 0
                self.gradientProtectionView.alpha = 0
                animateAlongside?()
            } completion: { _ in }
        } else {
            animateAlongside?()
        }
    }

    func play(animateAlongside: @escaping () -> Void) {
        videoPlayer?.play()

        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.bottomContentVStack.alpha = 1
            self.gradientProtectionView.alpha = 1
            animateAlongside()
        } completion: { _ in

        }
    }

    var duration: CFTimeInterval {
        var duration: CFTimeInterval = 0
        var glyphCount: Int?
        switch item.attachment {
        case .pointer:
            owsFailDebug("Undownloaded attachments should not progress.")
            return 0
        case .stream(let stream):
            glyphCount = stream.caption?.glyphCount

            if let asset = videoPlayer?.avPlayer.currentItem?.asset {
                let videoDuration = CMTimeGetSeconds(asset.duration)
                if stream.isLoopingVideo {
                    // GIFs should loop 3 times, or play for 5 seconds
                    // whichever is longer.
                    duration = max(5, videoDuration * 3)
                } else {
                    // Videos should play for their duration
                    duration = videoDuration

                    // For now, we don't want to factor captions into video durations,
                    // as it would cause the video to loop leading to weird UX
                    glyphCount = nil
                }
            } else {
                // System stories play slightly longer.
                if item.message.authorAddress.isSystemStoryAddress {
                    // Based off glyph calculation below for the text
                    // embedded in the images in english.
                    duration = 10
                } else {
                    // At base static images should play for 5 seconds
                    duration = 5
                }
            }
        case .text(let attachment):
            glyphCount = attachment.text?.glyphCount

            // As a base, all text attachments play for at least 5s,
            // even if they have no text.
            duration = 5

            // If a text attachment includes a link preview, play
            // for an additional 2s
            if attachment.preview != nil { duration += 2 }
        }

        // If we have a glyph count, increase the duration to allow it to be readable
        if let glyphCount = glyphCount {
            // For each bucket of glyphs after the first 15,
            // add an additional 1s of playback time.
            let fifteenGlyphBuckets = (max(0, CGFloat(glyphCount) - 15) / 15).rounded(.up)
            duration += fifteenGlyphBuckets
        }

        return duration
    }

    var elapsedTime: CFTimeInterval? {
        guard let currentTime = videoPlayer?.avPlayer.currentTime(),
                let asset = videoPlayer?.avPlayer.currentItem?.asset else { return nil }
        let loopedElapsedTime = Double(videoPlayerLoopCount) * CMTimeGetSeconds(asset.duration)
        return CMTimeGetSeconds(currentTime) + loopedElapsedTime
    }

    private func startAttachmentDownloadIfNecessary(_ gesture: UITapGestureRecognizer) -> Bool {
        // Only start downloads when the user taps in the center of the view.
        let downloadHitRegion = CGRect(
            origin: CGPoint(x: frame.center.x - 30, y: frame.center.y - 30),
            size: CGSize(square: 60)
        )
        guard downloadHitRegion.contains(gesture.location(in: self)) else { return false }
        return item.startAttachmentDownloadIfNecessary { [weak self] in
            self?.updateMediaView()
        }
    }

    // MARK: - Author Row

    private lazy var timestampLabel = UILabel()
    private lazy var authorRow = UIStackView()
    private func createAuthorRow() {
        let (avatarView, nameLabel) = databaseStorage.read { (
            buildAvatarView(transaction: $0),
            buildNameLabel(transaction: $0)
        ) }

        let nameTrailingView: UIView
        let nameTrailingSpacing: CGFloat
        if item.message.authorAddress.isSystemStoryAddress {
            let icon = UIImageView(image: UIImage(named: "official-checkmark-20"))
            icon.contentMode = .center
            nameTrailingView = icon
            nameTrailingSpacing = 3
        } else {
            nameTrailingView = timestampLabel
            nameTrailingSpacing = 8
        }

        authorRow.addArrangedSubviews([
            avatarView,
            .spacer(withWidth: 12),
            nameLabel,
            .spacer(withWidth: nameTrailingSpacing),
            nameTrailingView,
            .hStretchingSpacer()
        ])
        authorRow.axis = .horizontal
        authorRow.alignment = .center

        timestampLabel.setCompressionResistanceHorizontalHigh()
        timestampLabel.setContentHuggingHorizontalHigh()
        timestampLabel.font = .ows_dynamicTypeFootnote
        timestampLabel.textColor = Theme.darkThemeSecondaryTextAndIconColor
        updateTimestampText()

        bottomContentVStack.addArrangedSubview(authorRow)
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
            config.dataSource = try? StoryUtil.authorAvatarDataSource(
                for: item.message,
                transaction: transaction
            )
        }

        switch item.message.context {
        case .groupId:
            guard
                let groupAvatarDataSource = try? StoryUtil.contextAvatarDataSource(
                    for: item.message,
                    transaction: transaction
                )
            else {
                owsFailDebug("Unexpectedly missing group avatar")
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
                config.dataSource = groupAvatarDataSource
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
        case .authorUuid, .privateStory, .none:
            return authorAvatarView
        }
    }

    private func buildNameLabel(transaction: SDSAnyReadTransaction) -> UIView {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = UIFont.ows_dynamicTypeSubheadline.ows_semibold
        label.text = StoryUtil.authorDisplayName(
            for: item.message,
            contactsManager: contactsManager,
            useFullNameForLocalAddress: false,
            transaction: transaction
        )
        return label
    }

    // MARK: - Caption

    private lazy var captionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 15/17
        label.textColor = Theme.darkThemePrimaryColor
        return label
    }()

    private var fullCaptionText: String?
    private var truncatedCaptionText: NSAttributedString?
    private var isCaptionTruncated: Bool { truncatedCaptionText != nil }
    private var hasCaption: Bool { fullCaptionText != nil }

    private var maxCaptionLines = 5
    private func createCaptionIfNecessary() {
        guard let captionText: String = {
            switch item.attachment {
            case .stream(let attachment): return attachment.caption?.nilIfEmpty
            case .pointer(let attachment): return attachment.caption?.nilIfEmpty
            case .text: return nil
            }
        }() else { return }

        fullCaptionText = captionText

        captionLabel.text = captionText

        bottomContentVStack.addArrangedSubview(captionLabel)
    }

    private var isCaptionExpanded = false
    private var captionBackdrop: UIView?
    private func toggleCaptionExpansionIfNecessary(_ gesture: UIGestureRecognizer) -> Bool {
        guard hasCaption, isCaptionTruncated else { return false }

        if !isCaptionExpanded {
            guard captionLabel.bounds.contains(gesture.location(in: captionLabel)) else { return false }
        } else if let captionBackdrop = captionBackdrop {
            guard captionBackdrop.bounds.contains(gesture.location(in: captionBackdrop)) else { return false }
        } else {
            owsFailDebug("Unexpectedly missing caption backdrop")
        }

        let isExpanding = !isCaptionExpanded
        isCaptionExpanded = isExpanding

        if isExpanding {
            self.captionBackdrop?.removeFromSuperview()
            let captionBackdrop = UIView()
            captionBackdrop.backgroundColor = .ows_blackAlpha60
            captionBackdrop.alpha = 0
            self.captionBackdrop = captionBackdrop
            insertSubview(captionBackdrop, belowSubview: bottomContentVStack)
            captionBackdrop.autoPinEdgesToSuperviewEdges()

            captionLabel.numberOfLines = 0
            captionLabel.text = fullCaptionText
            delegate?.storyItemMediaViewWantsToPause(self)
        } else {
            captionLabel.numberOfLines = maxCaptionLines
            captionLabel.attributedText = truncatedCaptionText
            delegate?.storyItemMediaViewWantsToPlay(self)
            updateCaptionTruncation()
        }

        UIView.animate(withDuration: 0.2) {
            self.captionBackdrop?.alpha = isExpanding ? 1 : 0
            self.captionLabel.layoutIfNeeded()
        } completion: { _ in
            if !isExpanding {
                self.captionBackdrop?.removeFromSuperview()
                self.captionBackdrop = nil
            }
        }

        return true
    }

    private var lastTruncationWidth: CGFloat?
    private func updateCaptionTruncation() {
        guard let fullCaptionText = fullCaptionText, !isCaptionExpanded else { return }

        // Only update truncation if the view's width has changed.
        guard width != lastTruncationWidth else { return }
        lastTruncationWidth = width

        captionLabel.numberOfLines = maxCaptionLines
        captionLabel.text = fullCaptionText
        bottomContentVStack.layoutIfNeeded()

        let labelMinimumScaledFont = captionLabel.font
            .withSize(captionLabel.font.pointSize * captionLabel.minimumScaleFactor)

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: captionLabel.bounds.size)
        let textStorage = NSTextStorage()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        textStorage.setAttributedString(fullCaptionText.styled(with: .font(labelMinimumScaledFont)))

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 5

        func visibleCaptionRange() -> NSRange {
            layoutManager.glyphRange(for: textContainer)
        }

        var visibleCharacterRangeUpperBound = visibleCaptionRange().upperBound

        // Check if we're displaying less than the full length of the caption text.
        guard visibleCharacterRangeUpperBound < fullCaptionText.utf16.count else {
            truncatedCaptionText = nil
            return
        }

        let readMoreText = NSLocalizedString(
            "STORIES_CAPTION_READ_MORE",
            comment: "Text indication a story caption can be tapped to read more."
        ).styled(with: .font(labelMinimumScaledFont.ows_semibold))

        var potentialTruncatedCaptionText = fullCaptionText
        func truncatePotentialCaptionText(to index: Int) {
            potentialTruncatedCaptionText = (potentialTruncatedCaptionText as NSString).substring(to: index)
            textStorage.setAttributedString(buildTruncatedCaptionText().styled(with: .font(labelMinimumScaledFont)))
        }

        func buildTruncatedCaptionText() -> NSAttributedString {
            .composed(of: [
                potentialTruncatedCaptionText.stripped, "…", " ", readMoreText
            ])
        }

        defer {
            truncatedCaptionText = buildTruncatedCaptionText()
            captionLabel.attributedText = truncatedCaptionText
        }

        // We might fit without further truncation, for example if the caption
        // contains new line characters, so set the possible new text immediately.
        truncatePotentialCaptionText(to: visibleCharacterRangeUpperBound)

        visibleCharacterRangeUpperBound = visibleCaptionRange().upperBound - readMoreText.string.utf16.count - 2

        // If we're still truncated, trim down the visible text until
        // we have space to fit the read more text without truncation.
        // This should only take a few iterations.
        var iterationCount = 0
        while visibleCharacterRangeUpperBound < potentialTruncatedCaptionText.utf16.count {
            let truncateToIndex = max(0, visibleCharacterRangeUpperBound)
            guard truncateToIndex > 0 else { break }

            truncatePotentialCaptionText(to: truncateToIndex)

            visibleCharacterRangeUpperBound = visibleCaptionRange().upperBound - readMoreText.string.utf16.count - 2

            iterationCount += 1
            if iterationCount >= 5 {
                owsFailDebug("Failed to calculate visible range for caption text. Bailing.")
                break
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCaptionTruncation()
    }

    // MARK: - Media

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
                let videoView = buildVideoView(originalMediaUrl: originalMediaUrl, shouldLoop: stream.isLoopingVideo)
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

    public func updateMuteState() {
        videoPlayer?.isMuted = delegate?.storyItemMediaViewShouldBeMuted(self) ?? false
    }

    private var videoPlayerLoopCount = 0
    private var videoPlayer: OWSVideoPlayer?
    private func buildVideoView(originalMediaUrl: URL, shouldLoop: Bool) -> UIView {
        let player = OWSVideoPlayer(url: originalMediaUrl, shouldLoop: shouldLoop, shouldMixAudioWithOthers: true)
        player.delegate = self
        self.videoPlayer = player
        updateMuteState()

        videoPlayerLoopCount = 0

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
        let progressView = CVAttachmentProgressView(
            direction: .download(attachmentPointer: pointer),
            diameter: 56,
            isDarkThemeEnabled: true,
            mediaCache: Self.mediaCache
        )

        let manualLayoutView = OWSLayerView(frame: .zero) { layerView in
            progressView.frame.size = progressView.layoutSize
            progressView.center = layerView.center
        }
        manualLayoutView.addSubview(progressView)

        return manualLayoutView
    }

    private func buildContentUnavailableView() -> UIView {
        // TODO: Error state
        return UIView()
    }
}

class StoryItem: NSObject {
    let message: StoryMessage
    let numberOfReplies: UInt
    enum Attachment {
        case pointer(TSAttachmentPointer)
        case stream(TSAttachmentStream)
        case text(TextAttachment)
    }
    var attachment: Attachment

    init(message: StoryMessage, numberOfReplies: UInt, attachment: Attachment) {
        self.message = message
        self.numberOfReplies = numberOfReplies
        self.attachment = attachment
    }
}

extension StoryItem {
    // MARK: - Downloading

    @discardableResult
    func startAttachmentDownloadIfNecessary(completion: (() -> Void)? = nil) -> Bool {
        guard case .pointer(let pointer) = attachment, ![.enqueued, .downloading].contains(pointer.state) else { return false }

        attachmentDownloads.enqueueDownloadOfAttachments(
            forStoryMessageId: message.uniqueId,
            attachmentGroup: .allAttachmentsIncoming,
            downloadBehavior: .bypassAll,
            touchMessageImmediately: true) { _ in
                Logger.info("Successfully re-downloaded attachment.")
                DispatchQueue.main.async { completion?() }
            } failure: { error in
                Logger.warn("Failed to redownload attachment with error: \(error)")
                DispatchQueue.main.async { completion?() }
            }

        return true
    }

    var isPendingDownload: Bool {
        guard case .pointer = attachment else { return false }
        return true
    }
}

extension StoryItemMediaView: OWSVideoPlayerDelegate {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: OWSVideoPlayer) {
        videoPlayerLoopCount += 1
    }
}
