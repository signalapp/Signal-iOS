//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AVFoundation

@objc
public protocol OWSVideoPlayerDelegate: AnyObject {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: OWSVideoPlayer)
}

@objc
public class OWSVideoPlayer: NSObject {

    @objc
    public let avPlayer: AVPlayer
    let audioActivity: AudioActivity
    let shouldLoop: Bool

    public var isMuted = false {
        didSet {
            avPlayer.volume = isMuted ? 0 : 1
        }
    }

    @objc
    weak public var delegate: OWSVideoPlayerDelegate?

    @objc
    convenience public init(url: URL) {
        self.init(url: url, shouldLoop: false)
    }

    @objc
    public init(url: URL, shouldLoop: Bool, shouldMixAudioWithOthers: Bool = false) {
        self.avPlayer = AVPlayer(url: url)
        self.audioActivity = AudioActivity(
            audioDescription: "[OWSVideoPlayer] url:\(url)",
            behavior: shouldMixAudioWithOthers ? .playbackMixWithOthers : .playback
        )
        self.shouldLoop = shouldLoop

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToCompletion(_:)),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: avPlayer.currentItem)
    }

    deinit {
        endAudioActivity()
    }

    // MARK: Playback Controls

    public func endAudioActivity() {
        audioSession.endAudioActivity(audioActivity)
    }

    @objc
    public func pause() {
        avPlayer.pause()
        endAudioActivity()
    }

    @objc
    public func play() {
        let success = audioSession.startAudioActivity(self.audioActivity)
        assert(success)

        guard let item = avPlayer.currentItem else {
            owsFailDebug("video player item was unexpectedly nil")
            return
        }

        if item.currentTime() == item.duration {
            // Rewind for repeated plays, but only if it previously played to end.
            avPlayer.seek(to: CMTime.zero)
        }

        avPlayer.play()
    }

    @objc
    public func stop() {
        avPlayer.pause()
        avPlayer.seek(to: CMTime.zero)
        endAudioActivity()
    }

    @objc(seekToTime:)
    public func seek(to time: CMTime) {
        // Seek with a tolerance (or precision) of a hundredth of a second.
        let tolerance = CMTime(seconds: 0.01, preferredTimescale: 1000)
        avPlayer.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    public var currentTimeSeconds: Double {
        return avPlayer.currentTime().seconds
    }

    // MARK: private

    @objc
    private func playerItemDidPlayToCompletion(_ notification: Notification) {
        self.delegate?.videoPlayerDidPlayToCompletion(self)
        if shouldLoop {
            avPlayer.seek(to: CMTime.zero)
            avPlayer.play()
        } else {
            endAudioActivity()
        }
    }
}
