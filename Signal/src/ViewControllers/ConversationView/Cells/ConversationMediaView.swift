//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class CVMediaView: UIView {

    private enum MediaError {
        case missing
        case invalid
        case failed
    }

    // MARK: -

    private let mediaCache: NSCache<NSString, AnyObject>
    public let attachment: TSAttachment
    private let isOutgoing: Bool
    private let maxMessageWidth: CGFloat
    private let isBorderless: Bool
    private var loadBlock : (() -> Void)?
    private var unloadBlock : (() -> Void)?

    // MARK: - LoadState

    // The loadState property allows us to:
    //
    // * Make sure we only have one load attempt
    //   enqueued at a time for a given piece of media.
    // * We never retry media that can't be loaded.
    // * We skip media loads which are no longer
    //   necessary by the time they reach the front
    //   of the queue.

    enum LoadState {
        case unloaded
        case loading
        case loaded
        case failed
    }

    // Thread-safe access to load state.
    //
    // We use a "box" class so that we can capture a reference
    // to this box (rather than self) and a) safely access
    // if off the main thread b) not prevent deallocation of
    // self.
    private class ThreadSafeLoadState {
        private var value: LoadState

        required init(_ value: LoadState) {
            self.value = value
        }

        func get() -> LoadState {
            objc_sync_enter(self)
            let valueCopy = value
            objc_sync_exit(self)
            return valueCopy
        }

        func set(_ newValue: LoadState) {
            objc_sync_enter(self)
            value = newValue
            objc_sync_exit(self)
        }
    }
    private let threadSafeLoadState = ThreadSafeLoadState(.unloaded)
    // Convenience accessors.
    private var loadState: LoadState {
        get {
            return threadSafeLoadState.get()
        }
        set {
            threadSafeLoadState.set(newValue)
        }
    }

    // MARK: - Initializers

    public required init(mediaCache: NSCache<NSString, AnyObject>,
                         attachment: TSAttachment,
                         isOutgoing: Bool,
                         maxMessageWidth: CGFloat,
                         isBorderless: Bool) {
        self.mediaCache = mediaCache
        self.attachment = attachment
        self.isOutgoing = isOutgoing
        self.maxMessageWidth = maxMessageWidth
        self.isBorderless = isBorderless

        super.init(frame: .zero)

        backgroundColor = isBorderless ? .clear : Theme.washColor
        clipsToBounds = true

        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    deinit {
        AssertIsOnMainThread()

        loadState = .unloaded
    }

    // MARK: -

    private func createContents() {
        AssertIsOnMainThread()

        guard let attachmentStream = attachment as? TSAttachmentStream else {
            return configureForUndownloadedImage()
        }
        guard !isFailedDownload else {
            configure(forError: .failed)
            return
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

    private func configureForUndownloadedImage() {
        tryToConfigureForBlurHash(attachment: attachment)

        guard !isFailedDownload else {
            return configure(forError: .failed)
        }

        guard !isPendingDownload else {
            return
        }

        addDownloadProgressIfNecessary()
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
        let attachmentId = attachmentPointer.uniqueId
        guard nil != attachmentDownloads.downloadProgress(forAttachmentId: attachmentId) else {
            // Not being downloaded.
            configure(forError: .missing)
            return
        }

        backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05)
        let progressView = MediaDownloadView(attachmentId: attachmentId, radius: 22, withCircle: true)
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
        let attachmentId = attachmentStream.uniqueId
        guard !attachmentStream.isUploaded else {
            return false
        }
        let progressView = MediaUploadView(attachmentId: attachmentId, radius: maxMessageWidth * 0.1)
        self.addSubview(progressView)
        progressView.autoPinEdgesToSuperviewEdges()
        return true
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
        let cacheKey = blurHash
        let stillImageView = UIImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        stillImageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        stillImageView.layer.minificationFilter = .trilinear
        stillImageView.layer.magnificationFilter = .trilinear
        stillImageView.backgroundColor = Theme.washColor
        addSubview(stillImageView)
        stillImageView.autoPinEdgesToSuperviewEdges()
        loadBlock = { [weak self] in
            AssertIsOnMainThread()

            if stillImageView.image != nil {
                owsFailDebug("Unexpectedly already loaded.")
                return
            }
            self?.tryToLoadMedia(loadMediaBlock: { () -> AnyObject? in
                guard let image = BlurHash.image(for: blurHash) else {
                    Logger.warn("Missing image for blurHash.")
                    return nil
                }
                return image
            },
                                 applyMediaBlock: { (media) in
                                    AssertIsOnMainThread()

                                    guard let image = media as? UIImage else {
                                        owsFailDebug("Media has unexpected type: \(type(of: media))")
                                        return
                                    }
                                    stillImageView.image = image
            },
                                 cacheKey: cacheKey)
        }
        unloadBlock = {
            AssertIsOnMainThread()

            stillImageView.image = nil
        }
    }

    private func configureForAnimatedImage(attachmentStream: TSAttachmentStream) {
        let cacheKey = attachmentStream.uniqueId
        let animatedImageView = YYAnimatedImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        animatedImageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        animatedImageView.layer.minificationFilter = .trilinear
        animatedImageView.layer.magnificationFilter = .trilinear
        animatedImageView.backgroundColor = isBorderless ? .clear : Theme.washColor
        addSubview(animatedImageView)
        animatedImageView.autoPinEdgesToSuperviewEdges()
        _ = addUploadProgressIfNecessary(animatedImageView)

        loadBlock = { [weak self] in
            AssertIsOnMainThread()

            guard let strongSelf = self else {
                return
            }

            if animatedImageView.image != nil {
                owsFailDebug("Unexpectedly already loaded.")
                return
            }
            strongSelf.tryToLoadMedia(loadMediaBlock: { () -> AnyObject? in
                guard attachmentStream.isValidImage else {
                    Logger.warn("Ignoring invalid attachment.")
                    return nil
                }
                guard let filePath = attachmentStream.originalFilePath else {
                    owsFailDebug("Attachment stream missing original file path.")
                    return nil
                }
                let animatedImage = YYImage(contentsOfFile: filePath)
                return animatedImage
            },
                                                        applyMediaBlock: { (media) in
                                                            AssertIsOnMainThread()

                                                            guard let image = media as? YYImage else {
                                                                owsFailDebug("Media has unexpected type: \(type(of: media))")
                                                                return
                                                            }
                                                            animatedImageView.image = image
            },
                                                        cacheKey: cacheKey)
        }
        unloadBlock = {
            AssertIsOnMainThread()

            animatedImageView.image = nil
        }
    }

    private func configureForStillImage(attachmentStream: TSAttachmentStream) {
        let cacheKey = attachmentStream.uniqueId
        let stillImageView = UIImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        stillImageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        stillImageView.layer.minificationFilter = .trilinear
        stillImageView.layer.magnificationFilter = .trilinear
        stillImageView.backgroundColor = isBorderless ? .clear : Theme.washColor
        addSubview(stillImageView)
        stillImageView.autoPinEdgesToSuperviewEdges()
        _ = addUploadProgressIfNecessary(stillImageView)
        loadBlock = { [weak self] in
            AssertIsOnMainThread()

            if stillImageView.image != nil {
                owsFailDebug("Unexpectedly already loaded.")
                return
            }
            self?.tryToLoadMedia(loadMediaBlock: { () -> AnyObject? in
                guard attachmentStream.isValidImage else {
                    Logger.warn("Ignoring invalid attachment.")
                    return nil
                }
                return attachmentStream.thumbnailImageLarge(success: { (image) in
                    AssertIsOnMainThread()

                    stillImageView.image = image
                }, failure: {
                    Logger.error("Could not load thumbnail")
                })
            },
                                 applyMediaBlock: { (media) in
                                    AssertIsOnMainThread()

                                    guard let image = media as? UIImage else {
                                        owsFailDebug("Media has unexpected type: \(type(of: media))")
                                        return
                                    }
                                    stillImageView.image = image
            },
                                                        cacheKey: cacheKey)
        }
        unloadBlock = {
            AssertIsOnMainThread()

            stillImageView.image = nil
        }
    }

    private func configureForVideo(attachmentStream: TSAttachmentStream) {
        let cacheKey = attachmentStream.uniqueId
        let stillImageView = UIImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        stillImageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        stillImageView.layer.minificationFilter = .trilinear
        stillImageView.layer.magnificationFilter = .trilinear
        stillImageView.backgroundColor = Theme.washColor

        addSubview(stillImageView)
        stillImageView.autoPinEdgesToSuperviewEdges()

        if !addUploadProgressIfNecessary(stillImageView) {
            let videoPlayButton = Self.buildVideoPlayButton {}
            videoPlayButton.isUserInteractionEnabled = false
            stillImageView.addSubview(videoPlayButton)
            videoPlayButton.autoCenterInSuperview()
        }

        loadBlock = { [weak self] in
            AssertIsOnMainThread()

            if stillImageView.image != nil {
                owsFailDebug("Unexpectedly already loaded.")
                return
            }
            self?.tryToLoadMedia(loadMediaBlock: { () -> AnyObject? in
                guard attachmentStream.isValidVideo else {
                    Logger.warn("Ignoring invalid attachment.")
                    return nil
                }
                return attachmentStream.thumbnailImageLarge(success: { (image) in
                    AssertIsOnMainThread()

                    stillImageView.image = image
                }, failure: {
                    Logger.error("Could not load thumbnail")
                })
            },
                                 applyMediaBlock: { (media) in
                                    AssertIsOnMainThread()

                                    guard let image = media as? UIImage else {
                                        owsFailDebug("Media has unexpected type: \(type(of: media))")
                                        return
                                    }
                                    stillImageView.image = image
            },
                                                        cacheKey: cacheKey)
        }
        unloadBlock = {
            AssertIsOnMainThread()

            stillImageView.image = nil
        }
    }

    @objc
    public static func buildVideoPlayButton(block: @escaping () -> Void) -> UIView {
        let playVideoButton = OWSButton(block: block)

        let playVideoCircleView = OWSLayerView(frame: .zero) { view in
            view.layer.cornerRadius = min(view.width, view.height) * 0.5
        }
        playVideoCircleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.7)
        playVideoCircleView.isUserInteractionEnabled = false
        playVideoButton.addSubview(playVideoCircleView)

        let playVideoIconView = UIImageView.withTemplateImageName("play-solid-32",
                                                                  tintColor: UIColor.ows_white)
        playVideoIconView.isUserInteractionEnabled = false
        playVideoButton.addSubview(playVideoIconView)

        let playVideoButtonWidth = ScaleFromIPhone5(44)
        let playVideoIconWidth = ScaleFromIPhone5(20)
        playVideoButton.autoSetDimensions(to: CGSize(square: playVideoButtonWidth))
        playVideoIconView.autoSetDimensions(to: CGSize(square: playVideoIconWidth))
        playVideoCircleView.autoPinEdgesToSuperviewEdges()
        playVideoIconView.autoCenterInSuperview()

        return playVideoButton
    }

    private var isPendingDownload: Bool {
        guard let attachmentPointer = attachment as? TSAttachmentPointer else {
            return false
        }
        return (attachmentPointer.state == .pendingMessageRequest ||
            attachmentPointer.state == .pendingManualDownload)

    }

    private var isFailedDownload: Bool {
        guard let attachmentPointer = attachment as? TSAttachmentPointer else {
            return false
        }
        return attachmentPointer.state == .failed
    }

    private var hasBlurHash: Bool {
        return BlurHash.isValidBlurHash(attachment.blurHash)
    }

    private func configure(forError error: MediaError) {
        backgroundColor = (Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05)
        let icon: UIImage
        switch error {
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
        iconView.tintColor = Theme.primaryTextColor.withAlphaComponent(0.6)
        addSubview(iconView)
        iconView.autoCenterInSuperview()
    }

    private func tryToLoadMedia(loadMediaBlock: @escaping () -> AnyObject?,
                                applyMediaBlock: @escaping (AnyObject) -> Void,
                                cacheKey: String) {
        AssertIsOnMainThread()

        // It's critical that we update loadState once
        // our load attempt is complete.
        let loadCompletion: (AnyObject?) -> Void = { [weak self] (possibleMedia) in
            AssertIsOnMainThread()

            guard let strongSelf = self else {
                return
            }
            guard strongSelf.loadState == .loading else {
                Logger.verbose("Skipping obsolete load.")
                return
            }
            guard let media = possibleMedia else {
                strongSelf.loadState = .failed
                // TODO:
                //            [self showAttachmentErrorViewWithMediaView:mediaView];
                return
            }

            applyMediaBlock(media)

            strongSelf.loadState = .loaded
        }

        guard loadState == .loading else {
            owsFailDebug("Unexpected load state: \(loadState)")
            return
        }

        let mediaCache = self.mediaCache
        if let media = mediaCache.object(forKey: cacheKey as NSString) {
            Logger.verbose("media cache hit")
            loadCompletion(media)
            return
        }

        Logger.verbose("media cache miss")

        let threadSafeLoadState = self.threadSafeLoadState
        CVMediaView.loadQueue.async {
            guard threadSafeLoadState.get() == .loading else {
                Logger.verbose("Skipping obsolete load.")
                return
            }

            guard let media = loadMediaBlock() else {
                Logger.info("Failed to load media.")

                DispatchQueue.main.async {
                    loadCompletion(nil)
                }
                return
            }

            DispatchQueue.main.async {
                mediaCache.setObject(media, forKey: cacheKey as NSString)

                loadCompletion(media)
            }
        }
    }

    // We use this queue to perform the media loads.
    // These loads are expensive, so we want to:
    //
    // * Do them off the main thread.
    // * Only do one at a time.
    // * Avoid this work if possible (obsolete loads for
    //   views that are no longer visible, redundant loads
    //   of media already being loaded, don't retry media
    //   that can't be loaded, etc.).
    // * Do them in _reverse_ order. More recently enqueued
    //   loads more closely reflect the current view state.
    //   By processing in reverse order, we improve our
    //   "skip rate" of obsolete loads.
    private static let loadQueue = ReverseDispatchQueue(label: "org.signal.asyncMediaLoadQueue")

    public func loadMedia() {
        AssertIsOnMainThread()

        switch loadState {
        case .unloaded:
            loadState = .loading

            guard let loadBlock = loadBlock else {
                return
            }
            loadBlock()
        case .loading, .loaded, .failed:
            break
        }
    }

    public func unloadMedia() {
        AssertIsOnMainThread()

        loadState = .unloaded

        guard let unloadBlock = unloadBlock else {
            return
        }
        unloadBlock()
    }
}
