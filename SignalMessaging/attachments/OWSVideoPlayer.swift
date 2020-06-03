//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

@objc
public protocol OWSVideoPlayerDelegate: class {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: OWSVideoPlayer)
}

@objc
public class OWSVideoPlayer: NSObject {

    @objc
    public let avPlayer: AVPlayer
    let audioActivity: AudioActivity
    let shouldLoop: Bool

    @objc
    weak public var delegate: OWSVideoPlayerDelegate?

    @objc
    convenience public init(url: URL) {
        self.init(url: url, shouldLoop: false)
    }

    @objc
    public init(url: URL, shouldLoop: Bool) {
        self.avPlayer = AVPlayer(url: url)
        self.audioActivity = AudioActivity(audioDescription: "[OWSVideoPlayer] url:\(url)", behavior: .playback)
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

    // MARK: Dependencies

    var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
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
