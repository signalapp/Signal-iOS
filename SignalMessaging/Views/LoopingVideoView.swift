//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import YYImage
import AVKit

/// Model object for a looping video asset
/// Any LoopingVideoViews playing this instance will all be kept in sync
@objc
public class LoopingVideo: NSObject {
    fileprivate let asset: AVAsset
    fileprivate let playerItem: AVPlayerItem
    fileprivate let player: AVPlayer

    @objc
    public convenience init?(url: URL) {
        guard OWSMediaUtils.isValidVideo(path: url.path) else { return nil }

        self.init(asset: AVAsset(url: url))
    }

    private init(asset: AVAsset) {
        self.asset = asset
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        super.init()

        player.isMuted = true
        player.allowsExternalPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false

        if #available(iOS 12, *) {
            player.preventsDisplaySleepDuringVideoPlayback = false
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToCompletion),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem)
    }

    /// Creates a copy of this object with an independent play lifecycle
    public func createIndependentCopy() -> LoopingVideo {
        LoopingVideo(asset: asset)
    }

    @objc private func playerItemDidPlayToCompletion() {
        player.seek(to: .zero)
        player.play()
    }

    // MARK: - Player count

    private var playerRefcount = AtomicUInt(0)

    fileprivate func incrementPlayerCount() {
        if playerRefcount.get() == 0 {
            player.seek(to: .zero)
            player.play()
        }
        playerRefcount.increment()
    }

    fileprivate func decrementPlayerCount() {
        playerRefcount.decrementOrZero()
    }
}

@objc
public class LoopingVideoView: UIView {

    @objc
    public var video: LoopingVideo? {
        didSet {
            guard video !== oldValue else { return }
            playerLayer.player = video?.player

            oldValue?.decrementPlayerCount()
            video?.incrementPlayerCount()
            kvoObserver = nil
        }
    }

    deinit {
        video?.decrementPlayerCount()
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
        guard let allVideoTracks = video?.asset.tracks(withMediaType: .video) else {
            return CGSize(square: UIView.noIntrinsicMetric)
        }

        return allVideoTracks
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
    private var kvoObserver: NSKeyValueObservation?

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
            kvoObserver = playerLayer.observe(
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
            kvoObserver = nil
            placeholderView?.removeFromSuperview()
            placeholderView = nil
        }
    }
}
