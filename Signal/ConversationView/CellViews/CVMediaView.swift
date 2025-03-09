//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI

public class CVMediaView: ManualLayoutViewWithLayer {

    // MARK: -

    private let mediaCache: CVMediaCache
    public let attachment: CVAttachment
    private let interaction: TSInteraction
    private let conversationStyle: ConversationStyle
    private let maxMessageWidth: CGFloat
    private let isBorderless: Bool
    private let isLoopingVideo: Bool
    private let thumbnailQuality: AttachmentThumbnailQuality
    private let isBroken: Bool
    private var reusableMediaView: ReusableMediaView?

    // MARK: - Initializers

    public init(
        mediaCache: CVMediaCache,
        attachment: CVAttachment,
        interaction: TSInteraction,
        maxMessageWidth: CGFloat,
        isBorderless: Bool,
        isLoopingVideo: Bool,
        isBroken: Bool,
        thumbnailQuality: AttachmentThumbnailQuality,
        conversationStyle: ConversationStyle
    ) {
        self.mediaCache = mediaCache
        self.attachment = attachment
        self.interaction = interaction
        self.maxMessageWidth = maxMessageWidth
        self.isBorderless = isBorderless
        self.isLoopingVideo = isLoopingVideo
        self.isBroken = isBroken
        self.thumbnailQuality = thumbnailQuality
        self.conversationStyle = conversationStyle

        super.init(name: "CVMediaView")

        backgroundColor = isBorderless ? .clear : Theme.washColor
        clipsToBounds = true

        createContents()
    }

    // MARK: -

    private func createContents() {
        AssertIsOnMainThread()

        switch attachment {
        case .undownloadable(let attachment):
            return configureForError(attachment: attachment.attachment)
        case .backupThumbnail(let thumbnail):
            configureForBackupThumbnailMedia(thumbnail.attachmentBackupThumbnail)
        case .pointer(let pointer, _):
            return configureForUndownloadedMedia(pointer.attachment)
        case .stream(let attachmentStream):
            let attachmentStream = attachmentStream.attachmentStream
            switch attachmentStream.contentType {
            case .image:
                configureForStillImage(attachmentStream: attachmentStream)
            case .animatedImage:
                configureForAnimatedImage(attachmentStream: attachmentStream)
            case .video where isLoopingVideo:
                configureForLoopingVideo(attachmentStream: attachmentStream)
            case .video:
                configureForVideo(attachmentStream: attachmentStream)
            case .audio, .file, .invalid:
                owsFailDebug("Attachment has unexpected type.")
                configureForError(attachment: attachmentStream.attachment)
            }
        }
    }

    private func configureForBackupThumbnailMedia(_ thumbnail: AttachmentBackupThumbnail) {
        configureForBackupThumbnail(attachmentBackupThumbnail: thumbnail)

        _ = addProgressIfNecessary()
    }

    private func configureForUndownloadedMedia(_ attachment: Attachment) {
        tryToConfigureForBlurHash(attachment: attachment)

        _ = addProgressIfNecessary()
    }

    private func addProgressIfNecessary() -> Bool {

        let direction: CVAttachmentProgressView.Direction
        switch CVAttachmentProgressView.progressType(
            forAttachment: attachment,
            interaction: interaction
        ) {
        case .none:
            return false
        case .uploading(let attachmentStream):
            direction = .upload(attachmentStream: attachmentStream)
        case .pendingDownload:
            // We don't need to add a download indicator for pending
            // attachments; CVComponentBodyMedia will add a download
            // button if any media in the gallery is pending.
            return false
        case .downloading(let attachmentPointer, let downloadState):
            backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05)

            direction = .download(
                attachmentPointer: attachmentPointer,
                downloadState: downloadState
            )
        case .unknown:
            owsFailDebug("Unknown progress type.")
            return false
        }

        let progressView = CVAttachmentProgressView(direction: direction,
                                                    isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
                                                    mediaCache: mediaCache)
        addSubviewToCenterOnSuperview(progressView, size: progressView.layoutSize)

        return true
    }

    private func configureImageView(_ imageView: UIImageView) {
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        imageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
    }

    private func applyReusableMediaView(_ reusableMediaView: ReusableMediaView) {
        reusableMediaView.owner = self
        self.reusableMediaView = reusableMediaView
        let mediaView = reusableMediaView.mediaView

        mediaView.removeFromSuperview()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        addSubviewToFillSuperviewEdges(mediaView)

        if let imageView = mediaView as? UIImageView {
            configureImageView(imageView)
        }
        mediaView.backgroundColor = isBorderless ? .clear : Theme.washColor

        if !addProgressIfNecessary() {
            if reusableMediaView.needsPlayButton {
                addVideoPlayButton()
            }
        }
    }

    private func createNewReusableMediaView(mediaViewAdapter: MediaViewAdapter, isAnimated: Bool) {
        let reusableMediaView = ReusableMediaView(mediaViewAdapter: mediaViewAdapter, mediaCache: mediaCache)
        mediaCache.setMediaView(reusableMediaView, forKey: mediaViewAdapter.cacheKey, isAnimated: isAnimated)
        applyReusableMediaView(reusableMediaView)
    }

    private func tryToConfigureForBlurHash(attachment: Attachment) {
        guard let blurHash = attachment.blurHash?.nilIfEmpty else { return }
        // NOTE: in the blurhash case, we use the blurHash itself as the
        // cachekey to avoid conflicts with the actual attachment contents.
        let cacheKey = CVMediaCache.CacheKey.blurHash(blurHash)
        let isAnimated = false
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterBlurHash(blurHash: blurHash)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: isAnimated)
    }

    private func configureForLoopingVideo(attachmentStream: AttachmentStream) {
        if let reusableMediaView = mediaCache.getMediaView(
            .attachment(attachmentStream.id),
            isAnimated: true
        ) {
            applyReusableMediaView(reusableMediaView)
        } else {
            createNewReusableMediaView(
                mediaViewAdapter: MediaViewAdapterLoopingVideo(
                    attachmentStream: attachmentStream),
                isAnimated: true)
        }
    }

    private func configureForAnimatedImage(attachmentStream: AttachmentStream) {
        let cacheKey = CVMediaCache.CacheKey.attachment(attachmentStream.id)
        let isAnimated = attachmentStream.contentType.isAnimatedImage
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterAnimated(attachmentStream: attachmentStream)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: isAnimated)
    }

    private func configureForStillImage(attachmentStream: AttachmentStream) {
        let cacheKey = CVMediaCache.CacheKey.attachment(attachmentStream.id)
        let isAnimated = attachmentStream.contentType.isAnimatedImage
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterStill(attachmentStream: attachmentStream,
                                                     thumbnailQuality: thumbnailQuality)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: isAnimated)
    }

    private func configureForVideo(attachmentStream: AttachmentStream) {
        let cacheKey = CVMediaCache.CacheKey.attachment(attachmentStream.id)
        let isAnimated = attachmentStream.contentType.isAnimatedImage
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterVideo(attachmentStream: attachmentStream,
                                                     thumbnailQuality: thumbnailQuality)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: isAnimated)
    }

    private func configureForBackupThumbnail(attachmentBackupThumbnail: AttachmentBackupThumbnail) {
        let cacheKey = CVMediaCache.CacheKey.backupThumbnail(attachmentBackupThumbnail.id)
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: false) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterBackupThumbnail(attachmentBackupThumbnail: attachmentBackupThumbnail)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: false)
    }

    private func addVideoPlayButton() {

        let playVideoButtonWidth: CGFloat = 44
        let playVideoIconWidth: CGFloat = 20

        let playVideoButton = UIView.transparentContainer()
        addSubviewToCenterOnSuperview(playVideoButton, size: CGSize(square: playVideoButtonWidth))

        let playVideoCircleView = OWSLayerView.circleView()
        playVideoCircleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.7)
        playVideoCircleView.isUserInteractionEnabled = false
        playVideoButton.addSubview(playVideoCircleView)
        layoutSubviewToFillSuperviewEdges(playVideoCircleView)

        let playVideoIconView = CVImageView()
        if isBroken {
            playVideoIconView.setTemplateImageName("play-slash-fill", tintColor: UIColor.ows_white)
        } else {
            playVideoIconView.setTemplateImageName("play-fill-32", tintColor: UIColor.ows_white)
        }
        playVideoIconView.isUserInteractionEnabled = false
        addSubviewToCenterOnSuperview(playVideoIconView,
                                      size: CGSize(square: playVideoIconWidth))
    }

    private var hasBlurHash: Bool {
        return BlurHash.isValidBlurHash(attachment.attachment.attachment.blurHash)
    }

    private func configureForError(attachment: Attachment) {
        if attachment.blurHash != nil {
            tryToConfigureForBlurHash(attachment: attachment)
        } else {
            backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05)
        }

        let backgroundSize: CGFloat = 44
        let background = UIView()
        background.backgroundColor = .black.withAlphaComponent(0.40)
        background.layer.cornerRadius = backgroundSize / 2
        addSubviewToCenterOnSuperview(background, size: .init(square: 44))

        let icon = UIImage(named: "photo-slash-36")!
        let iconView = CVImageView(image: icon)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        addSubviewToCenterOnSuperview(iconView, size: .init(square: 24))
    }

    public func loadMedia() {
        AssertIsOnMainThread()

        guard let reusableMediaView = reusableMediaView else {
            return
        }
        guard reusableMediaView.owner != nil else {
            Logger.warn("No longer owner of reusableMediaView.")
            return
        }
        guard reusableMediaView.owner == self else {
            owsFailDebug("No longer owner of reusableMediaView.")
            return
        }

        reusableMediaView.load()
    }

    public func unloadMedia() {
        AssertIsOnMainThread()

        guard let reusableMediaView = reusableMediaView else {
            return
        }
        guard reusableMediaView.owner == self else {
            // No longer owner of reusableMediaView.
            return
        }

        reusableMediaView.unload()
    }
}
