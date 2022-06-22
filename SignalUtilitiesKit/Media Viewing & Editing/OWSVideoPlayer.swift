//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import SessionMessagingKit

public protocol OWSVideoPlayerDelegate: AnyObject {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: OWSVideoPlayer)
}

public class OWSVideoPlayer {

    public let avPlayer: AVPlayer
    let audioActivity: AudioActivity

    public weak var delegate: OWSVideoPlayerDelegate?

    @objc public init(url: URL) {
        self.avPlayer = AVPlayer(url: url)
        self.audioActivity = AudioActivity(audioDescription: "[OWSVideoPlayer] url:\(url)", behavior: .playback)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToCompletion(_:)),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: avPlayer.currentItem)
    }

    // MARK: Playback Controls

    @objc
    public func pause() {
        avPlayer.pause()
        Environment.shared?.audioSession.endAudioActivity(self.audioActivity)
    }

    @objc
    public func play() {
        let success = (Environment.shared?.audioSession.startAudioActivity(self.audioActivity) == true)
        assert(success)

        guard let item = avPlayer.currentItem else {
            owsFailDebug("video player item was unexpectedly nil")
            return
        }

        if item.currentTime() == item.duration {
            // Rewind for repeated plays, but only if it previously played to end.
            avPlayer.seek(to: CMTime.zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        avPlayer.play()
    }

    @objc
    public func stop() {
        avPlayer.pause()
        avPlayer.seek(to: CMTime.zero, toleranceBefore: .zero, toleranceAfter: .zero)
        Environment.shared?.audioSession.endAudioActivity(self.audioActivity)
    }

    @objc(seekToTime:)
    public func seek(to time: CMTime) {
        avPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: private

    @objc
    private func playerItemDidPlayToCompletion(_ notification: Notification) {
        self.delegate?.videoPlayerDidPlayToCompletion(self)
        Environment.shared?.audioSession.endAudioActivity(self.audioActivity)
    }
}
