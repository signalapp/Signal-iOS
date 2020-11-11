//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

@objc
protocol OWSVideoPlayerDelegate: class {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: OWSVideoPlayer)
}

@objc
public class OWSVideoPlayer: NSObject {

    @objc
    let avPlayer: AVPlayer
    let audioActivity: AudioActivity

    @objc
    weak var delegate: OWSVideoPlayerDelegate?

    @objc init(url: URL) {
        self.avPlayer = AVPlayer(url: url)
        self.audioActivity = AudioActivity(audioDescription: "[OWSVideoPlayer] url:\(url)", behavior: .playback)

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToCompletion(_:)),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: avPlayer.currentItem)
    }

    // MARK: Dependencies

    var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    // MARK: Playback Controls

    @objc
    public func pause() {
        avPlayer.pause()
        audioSession.endAudioActivity(self.audioActivity)
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
        audioSession.endAudioActivity(self.audioActivity)
    }

    @objc(seekToTime:)
    public func seek(to time: CMTime) {
        avPlayer.seek(to: time)
    }

    // MARK: private

    @objc
    private func playerItemDidPlayToCompletion(_ notification: Notification) {
        self.delegate?.videoPlayerDidPlayToCompletion(self)
        audioSession.endAudioActivity(self.audioActivity)
    }
}
