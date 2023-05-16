//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import YYImage
import AVKit

/// Model object for a looping video asset
/// Any LoopingVideoViews playing this instance will all be kept in sync
public class LoopingVideo: NSObject {
    fileprivate var asset: AVAsset

    public init?(url: URL) {
        guard OWSMediaUtils.isVideoOfValidContentTypeAndSize(path: url.path) else {
            return nil
        }
        self.asset = AVAsset(url: url)
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
                firstly(on: DispatchQueue.global(qos: .userInitiated)) { [weak self] () -> Void in
                    guard let self = self else {
                        return
                    }
                    let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["tracks"])
                    self.player.replaceCurrentItem(with: playerItem)
                    self.player.play()
                }.done(on: DispatchQueue.main) { [weak self] in
                    guard let self = self else {
                        return
                    }
                    self.invalidateIntrinsicContentSize()
                    self.delegate?.loopingVideoViewChangedPlayerItem()
                }
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
                CGSizeMax($0, $1)
            }
    }
}
