//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import UIKit

public protocol VideoPlayerViewDelegate: AnyObject {
    func videoPlayerViewStatusDidChange(_ view: VideoPlayerView)
    func videoPlayerViewPlaybackTimeDidChange(_ view: VideoPlayerView)
}

// MARK: -

public class VideoPlayerView: UIView {

    // MARK: - Properties

    public weak var delegate: VideoPlayerViewDelegate?

    public var videoPlayer: VideoPlayer? {
        didSet {
            player = videoPlayer?.avPlayer
        }
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

    public var player: AVPlayer? {
        get {
            AssertIsOnMainThread()

            return playerLayer.player
        }
        set {
            AssertIsOnMainThread()

            removeKVO(player: playerLayer.player)

            playerLayer.player = newValue

            addKVO(player: playerLayer.player)

            invalidateIntrinsicContentSize()
        }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    // Override UIView property
    override public static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    public var isPlaying: Bool {
        guard let videoPlayer else {
            return false
        }
        return videoPlayer.isPlaying
    }

    public var currentTimeSeconds: Double {
        guard let videoPlayer else {
            return 0
        }
        return videoPlayer.currentTimeSeconds
    }

    // MARK: - Initializers

    public init() {
        super.init(frame: .zero)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeKVO(player: player)
    }

    // MARK: -

    override public var intrinsicContentSize: CGSize {
        guard let player = self.player,
              let playerItem = player.currentItem else {
            return CGSize(square: UIView.noIntrinsicMetric)
        }

        return playerItem.asset.tracks(withMediaType: .video)
            .map { (assetTrack: AVAssetTrack) -> CGSize in
                assetTrack.naturalSize.applying(assetTrack.preferredTransform).abs
            }.reduce(.zero) {
                CGSizeMax($0, $1)
            }
    }

    // MARK: - KVO

    private var playerObservers = [NSKeyValueObservation]()
    private var periodicTimeObserver: Any?

    private func addKVO(player: AVPlayer?) {
        guard let player = player else {
            return
        }

        // Observe status changes: anything that might affect "isPlaying".
        let changeHandler = { [weak self] (_: AVPlayer, _: Any) in
            guard let self = self else { return }
            self.delegate?.videoPlayerViewStatusDidChange(self)
        }
        playerObservers = [
            player.observe(\AVPlayer.status, options: [.new, .initial], changeHandler: changeHandler),
            player.observe(\AVPlayer.timeControlStatus, options: [.new, .initial], changeHandler: changeHandler),
            player.observe(\AVPlayer.rate, options: [.new, .initial], changeHandler: changeHandler)
        ]

        // Observe playback progress.
        let interval = CMTime(seconds: 0.01, preferredTimescale: 1000)
        periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.videoPlayerViewPlaybackTimeDidChange(self)
        }
    }

    private func removeKVO(player: AVPlayer?) {
        playerObservers.forEach { $0.invalidate() }
        playerObservers.removeAll()

        guard let player else { return }

        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil
    }

    // MARK: - Playback

    public func pause() {
        guard let videoPlayer else {
            owsFailDebug("Missing videoPlayer.")
            return
        }

        videoPlayer.pause()
    }

    public func play() {
        guard let videoPlayer else {
            owsFailDebug("Missing videoPlayer.")
            return
        }

        videoPlayer.play()
    }

    public func stop() {
        guard let videoPlayer else {
            owsFailDebug("Missing videoPlayer.")
            return
        }

        videoPlayer.stop()
    }

    public func seek(to time: CMTime) {
        guard let videoPlayer else {
            owsFailDebug("Missing videoPlayer.")
            return
        }

        videoPlayer.seek(to: time)
    }
}
