//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ConversationMediaView: UIView {
    private let mediaCache: NSCache<NSString, AnyObject>
    private let attachment: TSAttachment
    private var loadBlock : (() -> Void)?
    private var unloadBlock : (() -> Void)?
    private var didFailToLoad = false

    @objc
    public required init(mediaCache: NSCache<NSString, AnyObject>,
                         attachment: TSAttachment) {
        self.mediaCache = mediaCache
        self.attachment = attachment

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
            // TODO: Handle this case.
            owsFailDebug("Missing attachment stream.")
            return
        }
        if attachmentStream.isAnimated {
            configureForAnimatedImage(attachmentStream: attachmentStream)
        } else if attachmentStream.isImage {
            configureForStillImage(attachmentStream: attachmentStream)
        } else if attachmentStream.isVideo {
            configureForVideo(attachmentStream: attachmentStream)
        } else {
            // TODO: Handle this case.
            owsFailDebug("Attachment has unexpected type.")
        }
    }

    private func addMediaSubview(_ subview: UIView) {
        addSubview(subview)
        subview.autoPinEdgesToSuperviewEdges()
        // TODO: Possibly add upload/download indicator here.
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
        addMediaSubview(animatedImageView)
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
        addMediaSubview(stillImageView)
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
        addMediaSubview(stillImageView)

        // TODO: Hide during upload/download.
        let videoPlayIcon = UIImage(named: "play_button")
        let videoPlayButton = UIImageView(image: videoPlayIcon)
        stillImageView.addSubview(videoPlayButton)
        videoPlayButton.autoCenterInSuperview()

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
            owsFailDebug("Missing loadBlock")
            return
        }
        loadBlock()
    }

    @objc
    public func unloadMedia() {
        AssertIsOnMainThread()

        guard let unloadBlock = unloadBlock else {
            owsFailDebug("Missing unloadBlock")
            return
        }
        unloadBlock()
    }
}
