//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public class CVMediaView: UIView {

    private enum MediaError {
        case missing
        case invalid
    }

    // MARK: -

    private let mediaCache: CVMediaCache
    public let attachment: TSAttachment
    private let interaction: TSInteraction
    private let conversationStyle: ConversationStyle
    private let maxMessageWidth: CGFloat
    private let isBorderless: Bool

    private var reusableMediaView: ReusableMediaView?

    // MARK: - Initializers

    public required init(mediaCache: CVMediaCache,
                         attachment: TSAttachment,
                         interaction: TSInteraction,
                         maxMessageWidth: CGFloat,
                         isBorderless: Bool,
                         conversationStyle: ConversationStyle) {
        self.mediaCache = mediaCache
        self.attachment = attachment
        self.interaction = interaction
        self.maxMessageWidth = maxMessageWidth
        self.isBorderless = isBorderless
        self.conversationStyle = conversationStyle

        super.init(frame: .zero)

        backgroundColor = isBorderless ? .clear : Theme.washColor
        clipsToBounds = true

        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: -

    private func createContents() {
        AssertIsOnMainThread()

        guard let attachmentStream = attachment as? TSAttachmentStream else {
            return configureForUndownloadedMedia()
        }
        if attachmentStream.shouldBeRenderedByYY {
            configureForAnimatedImage(attachmentStream: attachmentStream)
        } else if attachmentStream.isImage {
            configureForStillImage(attachmentStream: attachmentStream)
        } else if attachmentStream.isVideo {
            configureForVideo(attachmentStream: attachmentStream)
        } else {
            owsFailDebug("Attachment has unexpected type.")
            configure(forError: .invalid)
        }
    }

    private func configureForUndownloadedMedia() {
        tryToConfigureForBlurHash(attachment: attachment)

        _ = addProgressIfNecessary()
    }

    private func addProgressIfNecessary() -> Bool {

        let direction: CVAttachmentProgressView.Direction
        switch CVAttachmentProgressView.progressType(forAttachment: attachment,
                                                     interaction: interaction) {
        case .none:
            return false
        case .uploading(let attachmentStream):
            direction = .upload(attachmentStream: attachmentStream)
        case .pendingDownload:
            // We don't need to add a download indicator for pending
            // attachments; CVComponentBodyMedia will add a download
            // button if any media in the gallery is pending.
            return false
        case .downloading(let attachmentPointer):
            backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05)

            direction = .download(attachmentPointer: attachmentPointer)
        case .restoring:
            // TODO: We could easily show progress for restores.
            owsFailDebug("Restoring progress type.")
            return false
        case .unknown:
            owsFailDebug("Unknown progress type.")
            return false
        }

        let progressView = CVAttachmentProgressView(direction: direction,
                                                    style: .withCircle,
                                                    conversationStyle: conversationStyle)
        addSubview(progressView)
        progressView.autoCenterInSuperview()
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
        addSubview(mediaView)
        mediaView.autoPinEdgesToSuperviewEdges()
        if let imageView = mediaView as? UIImageView {
            configureImageView(imageView)
        }
        mediaView.backgroundColor = isBorderless ? .clear : Theme.washColor

        if !addProgressIfNecessary() {
            if reusableMediaView.isVideo {
                let videoPlayButton = Self.buildVideoPlayButton()
                addSubview(videoPlayButton)
                videoPlayButton.autoCenterInSuperview()
            }
        }
    }

    private func createNewReusableMediaView(mediaViewAdapter: MediaViewAdapter, isAnimated: Bool) {
        let reusableMediaView = ReusableMediaView(mediaViewAdapter: mediaViewAdapter, mediaCache: mediaCache)
        mediaCache.setMediaView(reusableMediaView, forKey: mediaViewAdapter.cacheKey, isAnimated: isAnimated)
        applyReusableMediaView(reusableMediaView)
    }

    private func tryToConfigureForBlurHash(attachment: TSAttachment) {
        guard let pointer = attachment as? TSAttachmentPointer else {
            owsFailDebug("Invalid attachment.")
            return
        }
        guard let blurHash = pointer.blurHash,
            blurHash.count > 0 else {
                return
        }
        // NOTE: in the blurhash case, we use the blurHash itself as the
        // cachekey to avoid conflicts with the actual attachment contents.
        let cacheKey = blurHash
        let isAnimated = false
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterBlurHash(blurHash: blurHash)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: isAnimated)
    }

    private func configureForAnimatedImage(attachmentStream: TSAttachmentStream) {
        let cacheKey = attachmentStream.uniqueId
        let isAnimated = attachmentStream.shouldBeRenderedByYY
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterAnimated(attachmentStream: attachmentStream)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: isAnimated)
    }

    private func configureForStillImage(attachmentStream: TSAttachmentStream) {
        let cacheKey = attachmentStream.uniqueId
        let isAnimated = attachmentStream.shouldBeRenderedByYY
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterStill(attachmentStream: attachmentStream)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: isAnimated)
    }

    private func configureForVideo(attachmentStream: TSAttachmentStream) {
        let cacheKey = attachmentStream.uniqueId
        let isAnimated = attachmentStream.shouldBeRenderedByYY
        if let reusableMediaView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
            applyReusableMediaView(reusableMediaView)
            return
        }

        let mediaViewAdapter = MediaViewAdapterVideo(attachmentStream: attachmentStream)
        createNewReusableMediaView(mediaViewAdapter: mediaViewAdapter, isAnimated: isAnimated)
    }

    private static func buildVideoPlayButton() -> UIView {
        let playVideoButton = UIView()

        let playVideoCircleView = OWSLayerView.circleView()
        playVideoCircleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.7)
        playVideoCircleView.isUserInteractionEnabled = false
        playVideoButton.addSubview(playVideoCircleView)

        let playVideoIconView = UIImageView.withTemplateImageName("play-solid-32",
                                                                  tintColor: UIColor.ows_white)
        playVideoIconView.isUserInteractionEnabled = false
        playVideoButton.addSubview(playVideoIconView)

        let playVideoButtonWidth: CGFloat = 44
        let playVideoIconWidth: CGFloat = 20
        playVideoButton.autoSetDimensions(to: CGSize(square: playVideoButtonWidth))
        playVideoIconView.autoSetDimensions(to: CGSize(square: playVideoIconWidth))
        playVideoCircleView.autoPinEdgesToSuperviewEdges()
        playVideoIconView.autoCenterInSuperview()

        return playVideoButton
    }

    private var hasBlurHash: Bool {
        return BlurHash.isValidBlurHash(attachment.blurHash)
    }

    private func configure(forError error: MediaError) {
        backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05)
        let icon: UIImage
        switch error {
        case .invalid:
            guard let asset = UIImage(named: "media_invalid") else {
                owsFailDebug("Missing image")
                return
            }
            icon = asset
        case .missing:
            return
        }
        let iconView = UIImageView(image: icon.withRenderingMode(.alwaysTemplate))
        iconView.tintColor = Theme.primaryTextColor.withAlphaComponent(0.6)
        addSubview(iconView)
        iconView.autoCenterInSuperview()
    }

    @objc
    public func loadMedia() {
        AssertIsOnMainThread()

        guard let reusableMediaView = reusableMediaView else {
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
