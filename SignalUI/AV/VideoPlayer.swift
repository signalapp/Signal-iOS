//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
public import SignalServiceKit

public protocol VideoPlayerDelegate: AnyObject {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: VideoPlayer)
}

public class VideoPlayer {

    public let avPlayer: AVPlayer
    private let audioActivity: AudioActivity
    private let shouldLoop: Bool

    public var isMuted = false {
        didSet {
            avPlayer.volume = isMuted ? 0 : 1
        }
    }

    weak public var delegate: VideoPlayerDelegate?

    public convenience init(decryptedFileUrl: URL) {
        self.init(decryptedFileUrl: decryptedFileUrl, shouldLoop: false)
    }

    public convenience init(decryptedFileUrl: URL, shouldLoop: Bool, shouldMixAudioWithOthers: Bool = false) {
        let avPlayer = AVPlayer(url: decryptedFileUrl)
        self.init(
            avPlayer: avPlayer,
            shouldLoop: shouldLoop,
            shouldMixAudioWithOthers: shouldMixAudioWithOthers,
            audioDescription: "[VideoPlayer] url:\(decryptedFileUrl)"
        )
    }

    public convenience init(
        attachment: ReferencedAttachmentStream,
        shouldMixAudioWithOthers: Bool = false
    ) throws {
        try self.init(
            attachment: attachment.attachmentStream,
            shouldLoop: attachment.reference.renderingFlag == .shouldLoop,
            shouldMixAudioWithOthers: shouldMixAudioWithOthers,
            audioDescription: attachment.reference.sourceFilename.map { "[VideoPlayer] \($0)" }
        )
    }

    public convenience init(
        attachment: AttachmentStream,
        shouldLoop: Bool,
        shouldMixAudioWithOthers: Bool = false
    ) throws {
        try self.init(
            attachment: attachment,
            shouldLoop: shouldLoop,
            shouldMixAudioWithOthers: shouldMixAudioWithOthers,
            audioDescription: nil
        )
    }

    private convenience init(
        attachment: AttachmentStream,
        shouldLoop: Bool,
        shouldMixAudioWithOthers: Bool,
        audioDescription: String?
    ) throws {
        let asset = try attachment.decryptedAVAsset()
        let playerItem = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.init(
            avPlayer: avPlayer,
            shouldLoop: shouldLoop,
            shouldMixAudioWithOthers: shouldMixAudioWithOthers,
            audioDescription: "[VideoPlayer]"
        )
    }

    public init(
        avPlayer: AVPlayer,
        shouldLoop: Bool,
        shouldMixAudioWithOthers: Bool = false,
        audioDescription: String = "[VideoPlayer]"
    ) {
        self.avPlayer = avPlayer
        audioActivity = AudioActivity(
            audioDescription: audioDescription,
            behavior: shouldMixAudioWithOthers ? .playbackMixWithOthers : .playback
        )
        self.shouldLoop = shouldLoop

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToCompletion(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem
        )
    }

    deinit {
        endAudioActivity()
    }

    // MARK: Playback Controls

    public func endAudioActivity() {
        SUIEnvironment.shared.audioSessionRef.endAudioActivity(audioActivity)
    }

    public func pause() {
        avPlayer.pause()
        endAudioActivity()
    }

    public func play() {
        let success = SUIEnvironment.shared.audioSessionRef.startAudioActivity(audioActivity)
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

    public func stop() {
        avPlayer.pause()
        avPlayer.seek(to: CMTime.zero)
        endAudioActivity()
    }

    public func seek(to time: CMTime) {
        owsAssertBeta(avPlayer.rate == 0 || avPlayer.rate == 1)
        // Seek with a tolerance (or precision) of a hundredth of a second.
        let tolerance = CMTime(seconds: 0.01, preferredTimescale: Self.preferredTimescale)
        // Bound the time
        var boundedTime = max(time, CMTime(seconds: 0, preferredTimescale: Self.preferredTimescale))
        boundedTime = min(boundedTime, avPlayer.currentItem?.asset.duration ?? CMTime(seconds: 0, preferredTimescale: Self.preferredTimescale))
        avPlayer.seek(to: boundedTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    public func rewind(_ seconds: TimeInterval) {
        let newTime = avPlayer.currentTime() - CMTime(seconds: seconds, preferredTimescale: Self.preferredTimescale)
        seek(to: newTime)
    }

    public func fastForward(_ seconds: TimeInterval) {
        let newTime = avPlayer.currentTime() + CMTime(seconds: seconds, preferredTimescale: Self.preferredTimescale)
        seek(to: newTime)
    }

    private var playbackRateToRestore: Float?

    // Specify negative rate to rewind.
    public func changePlaybackRate(to rate: Float) {
        owsAssertBeta(abs(rate) > 1)
        playbackRateToRestore = avPlayer.rate
        if rate < 0 {
            avPlayer.isMuted = true
        }
        avPlayer.rate = rate
    }

    public func restorePlaybackRate() {
        avPlayer.isMuted = false
        if let playbackRateToRestore {
            avPlayer.rate = playbackRateToRestore
            self.playbackRateToRestore = nil
        }
    }

    public var isPlaying: Bool {
        if let playbackRateToRestore {
            // For UI consistency's sake, if currently playing at non-default speed
            // return `true` if rewind/fast forward started when player was playing.
            return playbackRateToRestore == 1
        }
        return avPlayer.timeControlStatus == .playing
    }

    public var currentTimeSeconds: Double {
        return avPlayer.currentTime().seconds
    }

    private static var preferredTimescale: CMTimeScale { 1000 }

    // MARK: private

    @objc
    private func playerItemDidPlayToCompletion(_ notification: Notification) {
        playbackRateToRestore = nil
        delegate?.videoPlayerDidPlayToCompletion(self)
        if shouldLoop {
            avPlayer.seek(to: CMTime.zero)
            avPlayer.play()
        } else {
            endAudioActivity()
        }
    }
}
