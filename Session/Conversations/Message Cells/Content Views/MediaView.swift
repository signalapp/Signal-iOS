// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import YYImage
import SessionUIKit
import SessionMessagingKit

public class MediaView: UIView {
    static let contentMode: UIView.ContentMode = .scaleAspectFill
    
    private enum MediaError {
        case missing
        case invalid
        case failed
    }

    // MARK: -

    private let mediaCache: NSCache<NSString, AnyObject>
    public let attachment: Attachment
    private let isOutgoing: Bool
    private let maxMessageWidth: CGFloat
    private var loadBlock: (() -> Void)?
    private var unloadBlock: (() -> Void)?

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

    private let loadState: Atomic<LoadState> = Atomic(.unloaded)

    // MARK: - Initializers

    public required init(
        mediaCache: NSCache<NSString, AnyObject>,
        attachment: Attachment,
        isOutgoing: Bool,
        maxMessageWidth: CGFloat
    ) {
        self.mediaCache = mediaCache
        self.attachment = attachment
        self.isOutgoing = isOutgoing
        self.maxMessageWidth = maxMessageWidth

        super.init(frame: .zero)

        themeBackgroundColor = .backgroundSecondary
        clipsToBounds = true

        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    deinit {
        loadState.mutate { $0 = .unloaded }
    }

    // MARK: -

    private func createContents() {
        AssertIsOnMainThread()

        guard attachment.state != .pendingDownload && attachment.state != .downloading else {
            addDownloadProgressIfNecessary()
            return
        }
        guard attachment.state != .failedDownload else {
            configure(forError: .failed)
            return
        }
        guard attachment.isValid else {
            configure(forError: .invalid)
            return
        }
        
        if attachment.isAnimated {
            configureForAnimatedImage(attachment: attachment)
        }
        else if attachment.isImage {
            configureForStillImage(attachment: attachment)
        }
        else if attachment.isVideo {
            configureForVideo(attachment: attachment)
        }
        else {
            owsFailDebug("Attachment has unexpected type.")
            configure(forError: .invalid)
        }
    }
    
    private func addDownloadProgressIfNecessary() {
        guard attachment.state != .failedDownload else {
            configure(forError: .failed)
            return
        }
        guard attachment.state != .uploading && attachment.state != .uploaded else {
            // TODO: Show "restoring" indicator and possibly progress.
            configure(forError: .missing)
            return
        }
        
        themeBackgroundColor = .backgroundSecondary
        let loader = MediaLoaderView()
        addSubview(loader)
        loader.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.bottom, UIView.HorizontalEdge.right ], to: self)
    }

    private func addUploadProgressIfNecessary(_ subview: UIView) -> Bool {
        guard isOutgoing else { return false }
        guard attachment.state != .failedUpload else {
            configure(forError: .failed)
            return false
        }
        
        // If this message was uploaded on a different device it'll now be seen as 'downloaded' (but
        // will still be outgoing - we don't want to show a loading indicator in this case)
        guard attachment.state != .uploaded && attachment.state != .downloaded else { return false }
        
        let loader = MediaLoaderView()
        addSubview(loader)
        loader.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.bottom, UIView.HorizontalEdge.right ], to: self)
        
        return true
    }

    private func configureForAnimatedImage(attachment: Attachment) {
        let animatedImageView: YYAnimatedImageView = YYAnimatedImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        animatedImageView.contentMode = MediaView.contentMode
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        animatedImageView.layer.minificationFilter = .trilinear
        animatedImageView.layer.magnificationFilter = .trilinear
        animatedImageView.themeBackgroundColor = .backgroundSecondary
        animatedImageView.isHidden = !attachment.isValid
        addSubview(animatedImageView)
        animatedImageView.autoPinEdgesToSuperviewEdges()
        _ = addUploadProgressIfNecessary(animatedImageView)

        loadBlock = { [weak self] in
            AssertIsOnMainThread()
            
            if animatedImageView.image != nil {
                owsFailDebug("Unexpectedly already loaded.")
                return
            }
            self?.tryToLoadMedia(
                loadMediaBlock: { applyMediaBlock in
                    guard attachment.isValid else {
                        self?.configure(forError: .invalid)
                        return
                    }
                    guard let filePath: String = attachment.originalFilePath else {
                        owsFailDebug("Attachment stream missing original file path.")
                        self?.configure(forError: .invalid)
                        return
                    }
                    
                    applyMediaBlock(YYImage(contentsOfFile: filePath))
                },
                applyMediaBlock: { media in
                    AssertIsOnMainThread()
                    
                    guard let image: YYImage = media as? YYImage else {
                        owsFailDebug("Media has unexpected type: \(type(of: media))")
                        self?.configure(forError: .invalid)
                        return
                    }
                    // FIXME: Animated images flicker when reloading the cells (even though they are in the cache)
                    animatedImageView.image = image
                },
                cacheKey: attachment.id
            )
        }
        unloadBlock = {
            AssertIsOnMainThread()

            animatedImageView.image = nil
        }
    }

    private func configureForStillImage(attachment: Attachment) {
        let stillImageView = UIImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        stillImageView.contentMode = MediaView.contentMode
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        stillImageView.layer.minificationFilter = .trilinear
        stillImageView.layer.magnificationFilter = .trilinear
        stillImageView.themeBackgroundColor = .backgroundSecondary
        stillImageView.isHidden = !attachment.isValid
        addSubview(stillImageView)
        stillImageView.autoPinEdgesToSuperviewEdges()
        _ = addUploadProgressIfNecessary(stillImageView)
        
        loadBlock = { [weak self] in
            AssertIsOnMainThread()

            if stillImageView.image != nil {
                owsFailDebug("Unexpectedly already loaded.")
                return
            }
            self?.tryToLoadMedia(
                loadMediaBlock: { applyMediaBlock in
                    guard attachment.isValid else {
                        self?.configure(forError: .invalid)
                        return
                    }
                    
                    attachment.thumbnail(
                        size: .large,
                        success: { image, _ in applyMediaBlock(image) },
                        failure: {
                            Logger.error("Could not load thumbnail")
                            self?.configure(forError: .invalid)
                        }
                    )
                },
                applyMediaBlock: { media in
                    AssertIsOnMainThread()
                    
                    guard let image: UIImage = media as? UIImage else {
                        owsFailDebug("Media has unexpected type: \(type(of: media))")
                        self?.configure(forError: .invalid)
                        return
                    }
                    
                    stillImageView.image = image
                },
                cacheKey: attachment.id
            )
        }
        unloadBlock = {
            AssertIsOnMainThread()

            stillImageView.image = nil
        }
    }

    private func configureForVideo(attachment: Attachment) {
        let stillImageView = UIImageView()
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        stillImageView.contentMode = MediaView.contentMode
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        stillImageView.layer.minificationFilter = .trilinear
        stillImageView.layer.magnificationFilter = .trilinear
        stillImageView.themeBackgroundColor = .backgroundSecondary
        stillImageView.isHidden = !attachment.isValid

        addSubview(stillImageView)
        stillImageView.autoPinEdgesToSuperviewEdges()

        if !addUploadProgressIfNecessary(stillImageView) {
            let videoPlayIcon = UIImage(named: "CirclePlay")
            let videoPlayButton = UIImageView(image: videoPlayIcon)
            videoPlayButton.set(.width, to: 72)
            videoPlayButton.set(.height, to: 72)
            stillImageView.addSubview(videoPlayButton)
            videoPlayButton.autoCenterInSuperview()
        }

        loadBlock = { [weak self] in
            AssertIsOnMainThread()

            if stillImageView.image != nil {
                owsFailDebug("Unexpectedly already loaded.")
                return
            }
            self?.tryToLoadMedia(
                loadMediaBlock: { applyMediaBlock in
                    guard attachment.isValid else {
                        self?.configure(forError: .invalid)
                        return
                    }
                    
                    attachment.thumbnail(
                        size: .medium,
                        success: { image, _ in applyMediaBlock(image) },
                        failure: {
                            Logger.error("Could not load thumbnail")
                            self?.configure(forError: .invalid)
                        }
                    )
                },
                applyMediaBlock: { media in
                    AssertIsOnMainThread()

                    guard let image: UIImage = media as? UIImage else {
                        owsFailDebug("Media has unexpected type: \(type(of: media))")
                        self?.configure(forError: .invalid)
                        return
                    }
                    
                    stillImageView.image = image
                },
                cacheKey: attachment.id
            )
        }
        unloadBlock = {
            AssertIsOnMainThread()

            stillImageView.image = nil
        }
    }

    private func configure(forError error: MediaError) {
        // When there is a failure in the 'loadMediaBlock' closure this can be called
        // on a background thread - rather than dispatching in every 'loadMediaBlock'
        // usage we just do so here
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.configure(forError: error)
            }
            return
        }
        
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
                
            case .missing: return
        }
        
        themeBackgroundColor = .backgroundSecondary
        
        // For failed ougoing messages add an overlay to make the icon more visible
        if isOutgoing {
            let attachmentOverlayView: UIView = UIView()
            attachmentOverlayView.themeBackgroundColor = .messageBubble_overlay
            addSubview(attachmentOverlayView)
            attachmentOverlayView.pin(to: self)
        }
        
        let iconView = UIImageView(image: icon.withRenderingMode(.alwaysTemplate))
        iconView.themeTintColor = .textPrimary
        iconView.alpha = Values.mediumOpacity
        addSubview(iconView)
        iconView.autoCenterInSuperview()
    }

    private func tryToLoadMedia(
        loadMediaBlock: @escaping (@escaping (AnyObject?) -> Void) -> Void,
        applyMediaBlock: @escaping (AnyObject) -> Void,
        cacheKey: String
    ) {
        // It's critical that we update loadState once
        // our load attempt is complete.
        let loadCompletion: (AnyObject?) -> Void = { [weak self] possibleMedia in
            guard self?.loadState.wrappedValue == .loading else {
                Logger.verbose("Skipping obsolete load.")
                return
            }
            guard let media: AnyObject = possibleMedia else {
                self?.loadState.mutate { $0 = .failed }
                // TODO:
                //            [self showAttachmentErrorViewWithMediaView:mediaView];
                return
            }
            
            applyMediaBlock(media)
            
            self?.mediaCache.setObject(media, forKey: cacheKey as NSString)
            self?.loadState.mutate { $0 = .loaded }
        }

        guard loadState.wrappedValue == .loading else {
            owsFailDebug("Unexpected load state: \(loadState)")
            return
        }

        if let media: AnyObject = self.mediaCache.object(forKey: cacheKey as NSString) {
            Logger.verbose("media cache hit")
            
            guard Thread.isMainThread else {
                DispatchQueue.main.async {
                    loadCompletion(media)
                }
                return
            }
            
            loadCompletion(media)
            return
        }

        Logger.verbose("media cache miss")

        MediaView.loadQueue.async { [weak self] in
            guard self?.loadState.wrappedValue == .loading else {
                Logger.verbose("Skipping obsolete load.")
                return
            }
            
            loadMediaBlock { media in
                guard Thread.isMainThread else {
                    DispatchQueue.main.async {
                        loadCompletion(media)
                    }
                    return
                }
                
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
        switch loadState.wrappedValue {
            case .unloaded:
                loadState.mutate { $0 = .loading }
                loadBlock?()
        
            case .loading, .loaded, .failed: break
        }
    }

    public func unloadMedia() {
        loadState.mutate { $0 = .unloaded }
        unloadBlock?()
    }
}
