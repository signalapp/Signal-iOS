//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVKit
public import SignalServiceKit

/// Model object for a looping video asset
/// Any LoopingVideoViews playing this instance will all be kept in sync
public class LoopingVideo: NSObject {
    fileprivate var asset: AVAsset

    public convenience init?(_ attachment: PreviewableAttachment) {
        self.init(decryptedLocalFileUrl: attachment.rawValue.dataSource.fileUrl)
    }

    public convenience init?(_ attachment: AttachmentStream) {
        guard let asset = try? attachment.decryptedAVAsset() else {
            return nil
        }
        self.init(asset: asset)
    }

    public convenience init?(decryptedLocalFileUrl url: URL) {
        do {
            try OWSMediaUtils.validateVideoExtension(ofPath: url.path)
            try OWSMediaUtils.validateVideoSize(atPath: url.path)
        } catch {
            return nil
        }
        self.init(asset: AVAsset(url: url))
    }

    public init(asset: AVAsset) {
        self.asset = asset
        super.init()
    }
}

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
        preventsDisplaySleepDuringVideoPlayback = false
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

    @objc
    private func playerItemDidPlayToCompletion(_ notification: NSNotification) {
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

// MARK: -

public protocol LoopingVideoViewDelegate: AnyObject {
    func loopingVideoViewChangedPlayerItem()
}

// MARK: -

public class LoopingVideoView: UIView {

    public weak var delegate: LoopingVideoViewDelegate?

    private let player = LoopingVideoPlayer()

    public var video: LoopingVideo? {
        didSet {
            guard video !== oldValue else { return }
            player.replaceCurrentItem(with: nil)
            invalidateIntrinsicContentSize()

            if let asset = video?.asset {
                let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["tracks"])
                self.player.replaceCurrentItem(with: playerItem)
                self.player.play()
                self.invalidateIntrinsicContentSize()
                self.delegate?.loopingVideoViewChangedPlayerItem()
            }
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
            return CGSize(square: UIView.noIntrinsicMetric)
        }

        // Tracks will always be loaded by LoopingVideo
        return asset.tracks(withMediaType: .video)
            .map { (assetTrack: AVAssetTrack) -> CGSize in
                assetTrack.naturalSize.applying(assetTrack.preferredTransform).abs
            }.reduce(.zero) {
                CGSize.max($0, $1)
            }
    }
}
