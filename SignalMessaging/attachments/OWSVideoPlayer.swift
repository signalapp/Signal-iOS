//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

@objc
protocol OWSVideoPlayerDelegate: class {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: OWSVideoPlayer)
}

@objc
public class OWSVideoPlayer: NSObject {

    let avPlayer: AVPlayer
    let audioActivity: AudioActivity

    weak var delegate: OWSVideoPlayerDelegate?

    init(url: URL) {
        self.avPlayer = AVPlayer(url: url)
        self.audioActivity = AudioActivity(audioDescription: "[OWSVideoPlayer] url:\(url)")

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToCompletion(_:)),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: avPlayer.currentItem)
    }

    // MARK: Playback Controls

    public func pause() {
        avPlayer.pause()
        OWSAudioSession.shared.endAudioActivity(self.audioActivity)
    }

    public func play() {
        OWSAudioSession.shared.startPlaybackAudioActivity(self.audioActivity)

        guard let item = avPlayer.currentItem else {
            owsFail("\(logTag) video player item was unexpectedly nil")
            return
        }

        if item.currentTime() == item.duration {
            // Rewind for repeated plays, but only if it previously played to end.
            avPlayer.seek(to: kCMTimeZero)
        }

        avPlayer.play()
    }

    public func stop() {
        avPlayer.pause()
        avPlayer.seek(to: kCMTimeZero)
        OWSAudioSession.shared.endAudioActivity(self.audioActivity)
    }

    @objc(seekToTime:)
    public func seek(to time: CMTime) {
        avPlayer.seek(to: time)
    }

    // MARK: private

    @objc
    private func playerItemDidPlayToCompletion(_ notification: Notification) {
        self.delegate?.videoPlayerDidPlayToCompletion(self)
        OWSAudioSession.shared.endAudioActivity(self.audioActivity)
    }
}
