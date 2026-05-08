//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVMediaView: ManualLayoutViewWithLayer {

    // MARK: -

    private let mediaCache: CVMediaCache
    let attachment: CVAttachment
    private let interaction: TSInteraction
    private let conversationStyle: ConversationStyle
    private let maxMessageWidth: CGFloat
    private let isBorderless: Bool
    private let isLoopingVideo: Bool
    private let thumbnailQuality: AttachmentThumbnailQuality
    private let isBroken: Bool
    private var reusableMediaView: ReusableMediaView?
    private var progressView: CVAttachmentProgressView?

    // Circular Play / Pause / Download progress etc
    private static let centerButtonSize: CGFloat = 44

    // MARK: - Public

    init(
        mediaCache: CVMediaCache,
        attachment: CVAttachment,
        interaction: TSInteraction,
        maxMessageWidth: CGFloat,
        isBorderless: Bool,
        isLoopingVideo: Bool,
        isBroken: Bool,
        thumbnailQuality: AttachmentThumbnailQuality,
        conversationStyle: ConversationStyle,
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

    func loadMedia() {
        AssertIsOnMainThread()

        guard let reusableMediaView else {
            return
        }
        guard reusableMediaView.owner != nil else {
            Logger.warn("No longer owner of reusableMediaView.")
            return
        }
        guard reusableMediaView.owner === self else {
            owsFailDebug("No longer owner of reusableMediaView.")
            return
        }

        reusableMediaView.load()
    }

    func unloadMedia() {
        AssertIsOnMainThread()

        guard let reusableMediaView else {
            return
        }
        guard reusableMediaView.owner === self else {
            // No longer owner of reusableMediaView.
            return
        }

        reusableMediaView.unload()
    }

    // MARK: -

    private func createContents() {
        AssertIsOnMainThread()

        switch attachment {
        case .undownloadable(let attachment):
            configureForError(attachment: attachment.attachment)

        case .backupThumbnail(let thumbnail):
            configureForBackupThumbnailMedia(thumbnail.attachmentBackupThumbnail)

        case .pointer(let pointer, _):
            configureForUndownloadedMedia(pointer.attachment)

        case .stream(let attachmentStream, isUploading: _, let imageMetadata):
            let attachmentStream = attachmentStream.attachmentStream
            switch attachmentStream.contentType {
            case .image:
                if let imageMetadata, imageMetadata.isAnimated {
                    configureForAnimatedImage(attachmentStream: attachmentStream)
                } else {
                    configureForStillImage(attachmentStream: attachmentStream)
                }
            case .video where isLoopingVideo:
                configureForLoopingVideo(attachmentStream: attachmentStream)
            case .video:
                configureForVideo(attachmentStream: attachmentStream)
            case .audio, .file:
                owsFailDebug("Attachment has unexpected type.")
                configureForError(attachment: attachmentStream.attachment)
            }
        }
    }

    private func configureForBackupThumbnailMedia(_ thumbnail: AttachmentBackupThumbnail) {
        configureForBackupThumbnail(attachmentBackupThumbnail: thumbnail)

        addProgressViewIfNeeded()
    }

    private func configureForUndownloadedMedia(_ attachment: Attachment) {
        if let thumbnail = attachment.asBackupThumbnail() {
            configureForBackupThumbnail(attachmentBackupThumbnail: thumbnail)
        } else {
            tryToConfigureForBlurHash(attachment: attachment)
        }

        addProgressViewIfNeeded()
    }

    @discardableResult
    private func addProgressViewIfNeeded() -> Bool {
        let direction: CVAttachmentProgressView.Direction
        switch CVAttachmentProgressView.progressType(
            cvAttachment: attachment,
        ) {
        case .none:
            removeProgressView()
            return false

        case .skipped:
            // We don't need to add a download indicator for pending
            // attachments; CVComponentBodyMedia will add a download
            // button if any media in the gallery is pending.
            removeProgressView()
            return false

        case .uploading(let attachmentStream):
            direction = .upload(attachmentStream: attachmentStream)

        case .downloading(let attachmentPointer, let downloadState):
            direction = .download(
                attachmentPointer: attachmentPointer,
                downloadState: downloadState,
            )
        }

        let progressView = ensureProgressView(direction: direction)
        if progressView.superview == nil {
            addSubviewToCenterOnSuperview(progressView, size: .square(44))
        }

        return true
    }

    private func ensureProgressView(direction: CVAttachmentProgressView.Direction) -> CVAttachmentProgressView {
        if let progressView {
            return progressView
        }
        let progressView = CVAttachmentProgressView(
            direction: direction,
            configuration: .forMediaOverlay(),
        )
        self.progressView = progressView
        return progressView
    }

    private func removeProgressView() {
        guard let progressView else { return }

        progressView.removeFromSuperview()
        self.progressView = nil
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

        if addProgressViewIfNeeded() == false, reusableMediaView.isVideo {
            addVideoPlayButton()
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
        if let reusableMediaView = mediaCache.getMediaView(.attachment(attachmentStream.id), isAnimated: true) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterLoopingVideo(attachmentStream: attachmentStream)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: true)
    }

    private func configureForAnimatedImage(attachmentStream: AttachmentStream) {
        let cacheKey = CVMediaCache.CacheKey.attachment(attachmentStream.id)
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: true) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterAnimated(attachmentStream: attachmentStream)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: true)
    }

    private func configureForStillImage(attachmentStream: AttachmentStream) {
        let cacheKey = CVMediaCache.CacheKey.attachment(attachmentStream.id)
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: false) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterStill(
            attachmentStream: attachmentStream,
            thumbnailQuality: thumbnailQuality,
        )
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: false)
    }

    private func configureForVideo(attachmentStream: AttachmentStream) {
        let cacheKey = CVMediaCache.CacheKey.attachment(attachmentStream.id)
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: false) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterVideo(
            attachmentStream: attachmentStream,
            thumbnailQuality: thumbnailQuality,
        )
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: false)
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
        let playIconImage = isBroken ? UIImage(named: "play-slash-fill")! : UIImage(named: "play-fill")!
        addIconOverCircularBlurBackground(playIconImage)
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

        addIconOverCircularBlurBackground(UIImage(named: "photo-slash")!)
    }

    private func addIconOverCircularBlurBackground(_ image: UIImage) {
        let circleView = ManualLayoutView.circleView(name: "circleView")
        circleView.clipsToBounds = true
        circleView.isUserInteractionEnabled = false
        addSubviewToCenterOnSuperview(circleView, size: CGSize(square: Self.centerButtonSize))

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        circleView.addSubviewToFillSuperviewEdges(blurView)

        let iconView = CVImageView(image: image)
        iconView.tintColor = .Signal.label
        iconView.isUserInteractionEnabled = false
        circleView.addSubviewToCenterOnSuperview(iconView, size: image.size)

    }
}
