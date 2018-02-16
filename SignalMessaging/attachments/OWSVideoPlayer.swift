//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

@objc
protocol OWSVideoPlayerDelegate: class {
    @available(iOSApplicationExtension 9.0, *)
    func videoPlayerDidPlayToCompletion(_ videoPlayer: OWSVideoPlayer)
}

@objc
public class OWSVideoPlayer: NSObject {

    let avPlayer: AVPlayer
    let audioActivity: AudioActivity

    weak var delegate: OWSVideoPlayerDelegate?

    @available(iOS 9.0, *)
    init(url: URL) {
        self.avPlayer = AVPlayer(url: url)
        self.audioActivity = AudioActivity(audioDescription:  "[OWSVideoPlayer] url:\(url)")

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToCompletion(_:)),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: avPlayer.currentItem)
    }

    // MARK: Playback Controls

    @available(iOS 9.0, *)
    public func pause() {
        avPlayer.pause()
        OWSAudioSession.shared.endAudioActivity(self.audioActivity)
    }

    @available(iOS 9.0, *)
    public func play() {
        OWSAudioSession.shared.setPlaybackCategory(audioActivity: self.audioActivity)

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

    @available(iOS 9.0, *)
    @objc(seekToTime:)
    public func seek(to time: CMTime) {
        avPlayer.seek(to: time)
    }

    // MARK: private

    @objc
    @available(iOS 9.0, *)
    private func playerItemDidPlayToCompletion(_ notification: Notification) {
        self.delegate?.videoPlayerDidPlayToCompletion(self)
        OWSAudioSession.shared.endAudioActivity(self.audioActivity)
    }
}
