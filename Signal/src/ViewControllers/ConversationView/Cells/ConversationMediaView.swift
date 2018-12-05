//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSConversationMediaView)
public class ConversationMediaView: UIView {

    private enum MediaError {
        case missing
        case invalid
        case failed
    }

    // MARK: - Dependencies

    private var attachmentDownloads: OWSAttachmentDownloads {
        return SSKEnvironment.shared.attachmentDownloads
    }

    // MARK: -

    private let mediaCache: NSCache<NSString, AnyObject>
    @objc
    public let attachment: TSAttachment
    private let isOutgoing: Bool
    private let maxMessageWidth: CGFloat
    private var loadBlock : (() -> Void)?
    private var unloadBlock : (() -> Void)?
    private var didFailToLoad = false

    @objc
    public required init(mediaCache: NSCache<NSString, AnyObject>,
                         attachment: TSAttachment,
                         isOutgoing: Bool,
                         maxMessageWidth: CGFloat) {
        self.mediaCache = mediaCache
        self.attachment = attachment
        self.isOutgoing = isOutgoing
        self.maxMessageWidth = maxMessageWidth

        super.init(frame: .zero)

        backgroundColor = Theme.offBackgroundColor
        clipsToBounds = true

        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private func createContents() {
        AssertIsOnMainThread()

        guard let attachmentStream = attachment as? TSAttachmentStream else {
            addDownloadProgressIfNecessary()
            return
        }
        guard !isFailedDownload else {
            configure(forError: .failed)
            return
        }
        if attachmentStream.isAnimated {
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

    private func addDownloadProgressIfNecessary() {
        guard !isFailedDownload else {
            configure(forError: .failed)
            return
        }
        guard let attachmentPointer = attachment as? TSAttachmentPointer else {
            owsFailDebug("Attachment has unexpected type.")
            configure(forError: .invalid)
            return
        }
        guard attachmentPointer.pointerType == .incoming else {
            // TODO: Show "restoring" indicator and possibly progress.
            configure(forError: .missing)
            return
        }
        guard let attachmentId = attachmentPointer.uniqueId else {
            owsFailDebug("Attachment missing unique ID.")
            configure(forError: .invalid)
            return
        }
        guard nil != attachmentDownloads.downloadProgress(forAttachmentId: attachmentId) else {
            // Not being downloaded.
            configure(forError: .missing)
            return
        }

        backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05)
        let progressView = MediaDownloadView(attachmentId: attachmentId, radius: maxMessageWidth * 0.1)
        self.addSubview(progressView)
        progressView.autoPinEdgesToSuperviewEdges()
    }

    private func addUploadProgressIfNecessary(_ subview: UIView) -> Bool {
        guard isOutgoing else {
            return false
        }
        guard let attachmentStream = attachment as? TSAttachmentStream else {
            return false
        }
        guard let attachmentId = attachmentStream.uniqueId else {
            owsFailDebug("Attachment missing unique ID.")
            configure(forError: .invalid)
            return false
        }
        guard !attachmentStream.isUploaded else {
            return false
        }
        let progressView = MediaUploadView(attachmentId: attachmentId, radius: maxMessageWidth * 0.1)
        self.addSubview(progressView)
        progressView.autoPinEdgesToSuperviewEdges()
        return true
    }

    private func configureForAnimatedImage(attachmentStream: TSAttachmentStream) {
        guard let cacheKey = attachmentStream.uniqueId else {
            owsFailDebug("Attachment stream missing unique ID.")
            return
        }
        let animatedImageView = YYAnimatedImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        animatedImageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        animatedImageView.layer.minificationFilter = kCAFilterTrilinear
        animatedImageView.layer.magnificationFilter = kCAFilterTrilinear
        animatedImageView.backgroundColor = Theme.offBackgroundColor
        addSubview(animatedImageView)
        animatedImageView.autoPinEdgesToSuperviewEdges()
        _ = addUploadProgressIfNecessary(animatedImageView)

        loadBlock = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            if animatedImageView.image != nil {
                return
            }
            let cachedValue = strongSelf.tryToLoadMedia(loadMediaBlock: { () -> AnyObject? in
                guard attachmentStream.isValidImage else {
                    owsFailDebug("Ignoring invalid attachment.")
                    return nil
                }
                guard let filePath = attachmentStream.originalFilePath else {
                    owsFailDebug("Attachment stream missing original file path.")
                    return nil
                }
                let animatedImage = YYImage(contentsOfFile: filePath)
                return animatedImage
            },
                                                        cacheKey: cacheKey,
                                                        canLoadAsync: true)
            guard let image = cachedValue as? YYImage else {
                return
            }
            animatedImageView.image = image
        }
        unloadBlock = {
            animatedImageView.image = nil
        }
    }

    private func configureForStillImage(attachmentStream: TSAttachmentStream) {
        guard let cacheKey = attachmentStream.uniqueId else {
            owsFailDebug("Attachment stream missing unique ID.")
            return
        }
        let stillImageView = UIImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        stillImageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        stillImageView.layer.minificationFilter = kCAFilterTrilinear
        stillImageView.layer.magnificationFilter = kCAFilterTrilinear
        stillImageView.backgroundColor = Theme.offBackgroundColor
        addSubview(stillImageView)
        stillImageView.autoPinEdgesToSuperviewEdges()
        _ = addUploadProgressIfNecessary(stillImageView)
        loadBlock = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            if stillImageView.image != nil {
                return
            }
            let cachedValue = strongSelf.tryToLoadMedia(loadMediaBlock: { () -> AnyObject? in
                guard attachmentStream.isValidImage else {
                    owsFailDebug("Ignoring invalid attachment.")
                    return nil
                }
                return attachmentStream.thumbnailImageMedium(success: { (image) in
                    stillImageView.image = image
                }, failure: {
                    Logger.error("Could not load thumbnail")
                })
            },
                                                        cacheKey: cacheKey,
                                                        canLoadAsync: true)
            guard let image = cachedValue as? UIImage else {
                return
            }
            stillImageView.image = image
        }
        unloadBlock = {
            stillImageView.image = nil
        }
    }

    private func configureForVideo(attachmentStream: TSAttachmentStream) {
        guard let cacheKey = attachmentStream.uniqueId else {
            owsFailDebug("Attachment stream missing unique ID.")
            return
        }
        let stillImageView = UIImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        stillImageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        stillImageView.layer.minificationFilter = kCAFilterTrilinear
        stillImageView.layer.magnificationFilter = kCAFilterTrilinear
        stillImageView.backgroundColor = Theme.offBackgroundColor

        addSubview(stillImageView)
        stillImageView.autoPinEdgesToSuperviewEdges()

        if !addUploadProgressIfNecessary(stillImageView) {
            let videoPlayIcon = UIImage(named: "play_button")
            let videoPlayButton = UIImageView(image: videoPlayIcon)
            stillImageView.addSubview(videoPlayButton)
            videoPlayButton.autoCenterInSuperview()
        }

        loadBlock = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            if stillImageView.image != nil {
                return
            }
            let cachedValue = strongSelf.tryToLoadMedia(loadMediaBlock: { () -> AnyObject? in
                guard attachmentStream.isValidVideo else {
                    owsFailDebug("Ignoring invalid attachment.")
                    return nil
                }
                return attachmentStream.thumbnailImageMedium(success: { (image) in
                    stillImageView.image = image
                }, failure: {
                    Logger.error("Could not load thumbnail")
                })
            },
                                                        cacheKey: cacheKey,
                                                        canLoadAsync: true)
            guard let image = cachedValue as? UIImage else {
                return
            }
            stillImageView.image = image
        }
        unloadBlock = {
            stillImageView.image = nil
        }
    }

    private var isFailedDownload: Bool {
        guard let attachmentPointer = attachment as? TSAttachmentPointer else {
            return false
        }
        return attachmentPointer.state == .failed
    }

    private func configure(forError error: MediaError) {
        backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05)
        let icon: UIImage
        switch (error) {
        case .failed:
            guard let asset = UIImage(named: "media_retry") else {
                owsFailDebug("Missing image")
                return
            }
            icon = asset
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
        iconView.tintColor = Theme.primaryColor.withAlphaComponent(0.6)
        addSubview(iconView)
        iconView.autoCenterInSuperview()
    }

    private func tryToLoadMedia(loadMediaBlock: @escaping () -> AnyObject?,
                                cacheKey: String,
                                canLoadAsync: Bool) -> AnyObject? {
        AssertIsOnMainThread()

        guard !didFailToLoad else {
            return nil
        }

        if let media = mediaCache.object(forKey: cacheKey as NSString) {
            Logger.verbose("media cache hit")
            return media
        }

        if let media = loadMediaBlock() {
            Logger.verbose("media cache miss")
            mediaCache.setObject(media, forKey: cacheKey as NSString)
            return media
        }
        guard canLoadAsync else {
            Logger.error("Failed to load media.")
            didFailToLoad = true
            // TODO:
            //            [self showAttachmentErrorViewWithMediaView:mediaView];
            return nil
        }
        return nil
    }

    @objc
    public func loadMedia() {
        AssertIsOnMainThread()

        guard let loadBlock = loadBlock else {
            return
        }
        loadBlock()
    }

    @objc
    public func unloadMedia() {
        AssertIsOnMainThread()

        guard let unloadBlock = unloadBlock else {
            return
        }
        unloadBlock()
    }
}
