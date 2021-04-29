//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import YYImage
import AVKit
import PromiseKit

/// Model object for a looping video asset
/// Any LoopingVideoViews playing this instance will all be kept in sync
@objc
public class LoopingVideo: NSObject {
    fileprivate let playerItemPromise: Guarantee<AVPlayerItem?>
    fileprivate var playerItem: AVPlayerItem? { playerItemPromise.value.flatMap { $0 } }
    fileprivate var asset: AVAsset? { playerItem?.asset }

    @objc
    public init?(url: URL) {
        guard OWSMediaUtils.isVideoOfValidContentTypeAndSize(path: url.path) else {
            return nil
        }
        playerItemPromise = firstly(on: .global(qos: .userInitiated)) {
            let asset = AVAsset(url: url)
            let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["tracks"])
            return OWSMediaUtils.isValidVideo(asset: asset) ? item : nil
        }
        super.init()
    }

    deinit {
        playerItem?.cancelPendingSeeks()
        asset?.cancelLoading()
    }
}

// TODO: Multicast for syncing up two views?
private class LoopingVideoPlayer: AVPlayer {

    override init() {
        super.init()
        sharedInit()
    }

    override init(url: URL) {
        super.init(url: url)
        sharedInit()

    }

    override init(playerItem item: AVPlayerItem?) {
        super.init(playerItem: item)
        sharedInit()
    }

    private func sharedInit() {
        if let item = currentItem {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.playerItemDidPlayToCompletion(_:)),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item)
        }

        isMuted = true
        allowsExternalPlayback = true
        if #available(iOS 12, *) {
            preventsDisplaySleepDuringVideoPlayback = false
        }
    }

    override func replaceCurrentItem(with newItem: AVPlayerItem?) {
        readyStatusObserver = nil

        if let oldItem = currentItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: oldItem)
            oldItem.cancelPendingSeeks()
        }

        super.replaceCurrentItem(with: newItem)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.playerItemDidPlayToCompletion(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: newItem)
    }

    @objc private func playerItemDidPlayToCompletion(_ notification: NSNotification) {
        guard (notification.object as AnyObject) === currentItem else { return }
        seek(to: .zero)
        play()
    }

    private var readyStatusObserver: NSKeyValueObservation?
    override public func play() {
        // Don't bother if we're already playing, or we don't have an item
        guard let item = currentItem, rate == 0 else { return }

        if item.status == .readyToPlay {
            readyStatusObserver = nil
            super.play()
        } else if readyStatusObserver == nil {
            // We're not ready to play, set up an observer to play when ready
            readyStatusObserver = item.observe(\.status) { [weak self] _, _  in
                guard let self = self, item === self.currentItem else { return }
                if item.status == .readyToPlay {
                    self.play()
                }
            }
        }
    }
}

@objc
public class LoopingVideoView: UIView {
    private let player = LoopingVideoPlayer()

    @objc
    public var video: LoopingVideo? {
        didSet {
            guard video !== oldValue else { return }
            player.replaceCurrentItem(with: nil)

            if let itemPromise = video?.playerItemPromise {
                itemPromise.done(on: .global(qos: .userInitiated)) { item in
                    guard item === self.video?.playerItem else { return }

                    if let item = item {
                        self.player.replaceCurrentItem(with: item)
                        self.player.play()
                    }
                }
            }
            displayReadyObserver = nil
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.player = player
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer {
        layer as? AVPlayerLayer ?? {
            owsFailDebug("Unexpected player type")
            return AVPlayerLayer()
        }()
    }

    override public var contentMode: UIView.ContentMode {
        didSet {
            switch contentMode {
            case .scaleAspectFill: playerLayer.videoGravity = .resizeAspectFill
            case .scaleToFill: playerLayer.videoGravity = .resize
            case .scaleAspectFit: playerLayer.videoGravity = .resizeAspect
            default: playerLayer.videoGravity = .resizeAspect
            }
        }
    }

    override public var intrinsicContentSize: CGSize {
        guard let asset = video?.asset else {
            // If we have an outstanding promise, invalidate the size once it's complete
            // If there isn't, -noIntrinsicMetric is valid
            if video?.playerItemPromise.isPending == true {
                video?.playerItemPromise.done { _ in self.invalidateIntrinsicContentSize() }
            }
            return CGSize(square: UIView.noIntrinsicMetric)
        }

        // Tracks will always be loaded by LoopingVideo
        return asset.tracks(withMediaType: .video)
            .map { $0.naturalSize }
            .reduce(.zero) {
                CGSize(width: max($0.width, $1.width),
                       height: max($0.height, $1.height))
            }
    }

    // MARK: - Placeholder Images

    /// AVKit may not have the video ready in time for display. If a closure is provided here, LoopingAnimationView will invoke the closure to
    /// fetch a placeholder image to present in the meantime while the video is prepared.
    /// This image will be removed once the video is ready to play.
    public var placeholderProvider: (() -> UIImage?)?

    private var placeholderView: UIImageView?
    private var displayReadyObserver: NSKeyValueObservation?

    override public func draw(_ rect: CGRect) {
        defer { super.draw(rect) }
        guard video != nil else { return }
        let isDisplayingPlaceholder = (placeholderView != nil)

        // If we aren't ready for display, add an imageView to present the placeholder. Start listening
        // for any changes so we can clean this up when the video layer is ready.
        if !playerLayer.isReadyForDisplay,
           !isDisplayingPlaceholder,
           let placeholderProvider = placeholderProvider {

            // First, set up our observer so we are notified once we can drop the placeholder
            displayReadyObserver = playerLayer.observe(
                \.isReadyForDisplay,
                options: .new
            ) { [weak self] (_, change) in
                if change.newValue == true {
                    self?.setNeedsDisplay()
                }
            }

            // Then, add the placeholder image
            let imageView = UIImageView()
            imageView.contentMode = contentMode
            imageView.image = placeholderProvider()

            addSubview(imageView)
            imageView.autoPinEdgesToSuperviewEdges()
            placeholderView = imageView

        } else if playerLayer.isReadyForDisplay {
            // Cleanup. The video is ready to go.
            displayReadyObserver = nil
            placeholderView?.removeFromSuperview()
            placeholderView = nil
        }
    }
}
