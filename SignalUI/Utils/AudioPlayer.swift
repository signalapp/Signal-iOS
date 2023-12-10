//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import MediaPlayer
import SignalCoreKit
import SignalMessaging

public enum AudioBehavior {
    case unknown
    case playback
    case playbackMixWithOthers
    case audioMessagePlayback
    case playAndRecord
    case call
}

public enum AudioPlaybackState {
    case stopped
    case playing
    case paused
}

public protocol AudioPlayerDelegate: AnyObject {

    var audioPlaybackState: AudioPlaybackState { get set }

    func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float)

    func audioPlayerDidFinish()
}

public class AudioPlayer: NSObject {

    public weak var delegate: AudioPlayerDelegate?

    public var duration: TimeInterval {
        audioPlayer?.duration ?? 0
    }

    // 1 (default) is normal playback speed. 0.5 is half speed, 2.0 is twice as fast.
    public var playbackRate: Float = 1 {
        didSet {
            if let audioPlayer, oldValue != playbackRate {
                audioPlayer.rate = playbackRate
            }
        }
    }

    public var isLooping: Bool = false

    private let mediaUrl: URL

    private var audioPlayer: AVAudioPlayer?

    private var audioPlayerPoller: Timer?

    private let audioActivity: AudioActivity

    public init(mediaUrl: URL, audioBehavior: AudioBehavior) {
        self.mediaUrl = mediaUrl
        audioActivity = AudioActivity(audioDescription: "\(Self.logTag()) \(mediaUrl)", behavior: audioBehavior)

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
    }

    deinit {
        DeviceSleepManager.shared.removeBlock(blockObject: self)
        stop()
    }

    // MARK: - Playback

    public func play() {
        AssertIsOnMainThread()

        let success = audioSession.startAudioActivity(audioActivity)
        owsAssertDebug(success)

        setupAudioPlayer()
        setupRemoteCommandCenter()

        delegate?.audioPlaybackState = .playing

        audioPlayer?.play()

        audioPlayerPoller?.invalidate()
        let audioPlayerPoller = Timer.weakTimer(
            withTimeInterval: 0.05,
            target: self,
            selector: #selector(audioPlayerUpdated(timer:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(audioPlayerPoller, forMode: .common)
        self.audioPlayerPoller = audioPlayerPoller

        // Prevent device from sleeping while playing audio.
        DeviceSleepManager.shared.addBlock(blockObject: self)
    }

    public func pause() {
        AssertIsOnMainThread()

        guard let audioPlayer else {
            owsFailDebug("audioPlayer == nil")
            return
        }

        delegate?.audioPlaybackState = .paused

        audioPlayer.pause()

        audioPlayerPoller?.invalidate()

        delegate?.setAudioProgress(audioPlayer.currentTime, duration: audioPlayer.duration, playbackRate: playbackRate)

        updateNowPlayingInfo()

        endAudioActivities()

        DeviceSleepManager.shared.removeBlock(blockObject: self)
    }

    public func setupAudioPlayer() {
        AssertIsOnMainThread()

        guard (delegate?.audioPlaybackState ?? .stopped) == .stopped else { return }

        guard audioPlayer == nil else {
            if delegate?.audioPlaybackState == .stopped {
                delegate?.audioPlaybackState = .paused
            }
            return
        }

        // In some cases, Android sends audio messages with the "audio/mpeg" content type. This
        // makes our choice of file extension ambiguous—`.mp3` or `.m4a`? AVFoundation uses the
        // extension to read the file, and if the extension is wrong, it won't be playable.
        //
        // In this case, we use a file type hint to tell AVFoundation to try the other type. This
        // is brittle but necessary to work around the buggy marriage of Android's content type and
        // AVFoundation's default behavior.
        //
        // Note that we probably still want this code even if Android updates theirs, because
        // iOS users might have existing attachments.
        //
        // See a similar comment in `AudioWaveformManager` and
        // <https://github.com/signalapp/Signal-iOS/issues/3590>.
        let fileTypeHint: AVFileType?
        lazy var isReadable = AVURLAsset(url: mediaUrl).isReadable
        switch mediaUrl.pathExtension {
        case "mp3": fileTypeHint = isReadable ? nil : AVFileType.m4a
        case "m4a": fileTypeHint = isReadable ? nil : AVFileType.mp3
        default: fileTypeHint = nil
        }

        let audioPlayer: AVAudioPlayer
        do {
            audioPlayer = try AVAudioPlayer(
                contentsOf: mediaUrl,
                fileTypeHint: fileTypeHint?.rawValue
            )
        } catch let error as NSError {
            Logger.error("Error: \(error)")
            stop()

            if error.domain == NSOSStatusErrorDomain {
                if error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile {
                    OWSActionSheets.showErrorAlert(
                        message: OWSLocalizedString(
                            "INVALID_AUDIO_FILE_ALERT_ERROR_MESSAGE",
                            comment: "Message for the alert indicating that an audio file is invalid."
                        )
                    )
                }
            }

            return
        }

        audioPlayer.delegate = self
        // Always enable playback rate from the start; it can only
        // be set before playing begins.
        audioPlayer.enableRate = true
        audioPlayer.rate = playbackRate
        audioPlayer.prepareToPlay()
        if isLooping {
            audioPlayer.numberOfLoops = -1
        }
        self.audioPlayer = audioPlayer

        if delegate?.audioPlaybackState == .stopped {
            delegate?.audioPlaybackState = .paused
        }
    }

    public func stop() {
        delegate?.audioPlaybackState = .stopped

        audioPlayer?.pause()
        audioPlayerPoller?.invalidate()

        delegate?.setAudioProgress(0, duration: 0, playbackRate: playbackRate)

        endAudioActivities()
        DeviceSleepManager.shared.removeBlock(blockObject: self)
        teardownRemoteCommandCenter()
    }

    private func endAudioActivities() {
        audioSession.endAudioActivity(audioActivity)
    }

    public func togglePlayState() {
        AssertIsOnMainThread()

        guard let delegate else { return }

        if delegate.audioPlaybackState == .playing {
            pause()
        } else {
            play()
        }
    }

    public func setCurrentTime(_ currentTime: TimeInterval) {
        setupAudioPlayer()

        guard let audioPlayer else {
            owsFailDebug("audioPlayer == nil")
            return
        }

        audioPlayer.currentTime = currentTime

        delegate?.setAudioProgress(audioPlayer.currentTime, duration: audioPlayer.duration, playbackRate: playbackRate)

        updateNowPlayingInfo()
    }

    // MARK: -

    @objc
    private func applicationDidEnterBackground() {
        guard !supportsBackgroundPlayback else { return }
        stop()
    }

    private var supportsBackgroundPlayback: Bool {
        audioActivity.supportsBackgroundPlayback
    }

    private var supportsBackgroundPlaybackControls: Bool {
        supportsBackgroundPlayback && !audioActivity.backgroundPlaybackName.isEmptyOrNil
    }

    private func updateNowPlayingInfo() {
        // Only update the now playing info if the activity supports background playback
        guard supportsBackgroundPlaybackControls else { return }

        guard
            let audioPlayer,
            let backgroundPlaybackName = audioActivity.backgroundPlaybackName, !backgroundPlaybackName.isEmpty
        else {
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: backgroundPlaybackName,
            MPMediaItemPropertyPlaybackDuration: audioPlayer.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audioPlayer.currentTime
        ]
    }

    private func setupRemoteCommandCenter() {
        guard supportsBackgroundPlaybackControls else { return }

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let changePlaybackPositionCommandEvent = event as? MPChangePlaybackPositionCommandEvent else {
                owsFailDebug("event is not MPChangePlaybackPositionCommandEvent")
                return .commandFailed
            }
            self?.setCurrentTime(changePlaybackPositionCommandEvent.positionTime)
            return .success
        }

        updateNowPlayingInfo()
    }

    private func teardownRemoteCommandCenter() {
        // If there's nothing left that wants background playback, disable lockscreen / control center controls
        guard !audioSession.wantsBackgroundPlayback else { return }

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Events

    @objc
    private func audioPlayerUpdated(timer: Timer) {
        AssertIsOnMainThread()

        owsAssertDebug(audioPlayerPoller != nil)
        guard let audioPlayer else {
            owsFailDebug("audioPlayer == nil")
            return
        }

        delegate?.setAudioProgress(audioPlayer.currentTime, duration: audioPlayer.duration, playbackRate: playbackRate)
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        AssertIsOnMainThread()

        stop()

        delegate?.audioPlayerDidFinish()
    }
}
