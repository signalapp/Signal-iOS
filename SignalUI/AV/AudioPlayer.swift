//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import MediaPlayer
public import SignalServiceKit

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
        _duration ?? 0
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

    private enum Source {
        case decryptedFile(URL)
        case attachment(AttachmentStream)

        var description: String {
            switch self {
            case .decryptedFile(let url):
                return url.absoluteString
            case .attachment(let attachment):
                return attachment.mimeType
            }
        }
    }

    private let source: Source

    private var audioPlayer: AVPlayer?

    private var audioPlayerPoller: Timer?

    private let audioActivity: AudioActivity

    private let sleepBlockObject = DeviceSleepManager.BlockObject(blockReason: "audio player")

    public convenience init(decryptedFileUrl: URL, audioBehavior: AudioBehavior) {
        self.init(source: .decryptedFile(decryptedFileUrl), audioBehavior: audioBehavior)
    }

    public convenience init?(attachment: SignalAttachment, audioBehavior: AudioBehavior) {
        guard let url = attachment.dataUrl else {
            return nil
        }
        self.init(source: .decryptedFile(url), audioBehavior: audioBehavior)
    }

    public convenience init(attachment: AttachmentStream, audioBehavior: AudioBehavior) {
        self.init(source: .attachment(attachment), audioBehavior: audioBehavior)
    }

    private init(source: Source, audioBehavior: AudioBehavior) {
        self.source = source
        audioActivity = AudioActivity(audioDescription: "\(Self.logTag()) \(source.description)", behavior: audioBehavior)

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
    }

    deinit {
        DeviceSleepManager.shared.removeBlock(blockObject: sleepBlockObject)
        stop()
    }

    // MARK: - Playback

    private var currentTime: TimeInterval {
        guard
            let cmTime = audioPlayer?.currentTime(),
            cmTime.timescale > 0
        else {
            return 0
        }
        return CMTimeGetSeconds(cmTime)
    }

    private var _duration: TimeInterval? {
        guard
            let cmTime = audioPlayer?.currentItem?.duration,
            cmTime.timescale > 0
        else {
            return nil
        }
        return CMTimeGetSeconds(cmTime)
    }

    private var timescale: CMTimeScale {
        guard
            let timescale = audioPlayer?.currentItem?.duration.timescale,
            timescale > 0
        else {
            return 44100
        }
        return timescale
    }

    public func play() {
        AssertIsOnMainThread()

        let success = SUIEnvironment.shared.audioSessionRef.startAudioActivity(audioActivity)
        owsAssertDebug(success)

        setupAudioPlayer()
        setupRemoteCommandCenter()

        delegate?.audioPlaybackState = .playing

        audioPlayer?.playImmediately(atRate: playbackRate)

        audioPlayerPoller?.invalidate()
        let audioPlayerPoller = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.audioPlayerUpdated(timer: timer)
        }
        RunLoop.main.add(audioPlayerPoller, forMode: .common)
        self.audioPlayerPoller = audioPlayerPoller

        // Prevent device from sleeping while playing audio.
        DeviceSleepManager.shared.addBlock(blockObject: sleepBlockObject)
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

        delegate?.setAudioProgress(self.currentTime, duration: self.duration, playbackRate: playbackRate)

        updateNowPlayingInfo()

        endAudioActivities()

        DeviceSleepManager.shared.removeBlock(blockObject: sleepBlockObject)
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

        func makeAudioPlayer(mediaUrl: URL) throws -> AVPlayer {
            var asset = AVURLAsset(url: mediaUrl)
            if !asset.isReadable {
                if let extensionOverride = MimeTypeUtil.alternativeAudioFileExtension(fileExtension: mediaUrl.pathExtension) {
                    let symlinkUrl = OWSFileSystem.temporaryFileUrl(
                        fileExtension: extensionOverride,
                        isAvailableWhileDeviceLocked: true
                    )
                    try FileManager.default.createSymbolicLink(
                        at: symlinkUrl,
                        withDestinationURL: mediaUrl
                    )
                    asset = AVURLAsset(url: symlinkUrl)
                }
            }
            return AVPlayer(playerItem: .init(asset: asset))
        }

        let audioPlayer: AVPlayer
        do {
            switch source {
            case .decryptedFile(let url):
                audioPlayer = try makeAudioPlayer(mediaUrl: url)
            case .attachment(let attachment):
                let asset = try attachment.decryptedAVAsset()
                audioPlayer = .init(playerItem: .init(asset: asset))
            }
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioPlayerDidFinishPlaying),
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: audioPlayer.currentItem
        )
        audioPlayer.rate = playbackRate
        // Pause it; it starts off playing.
        audioPlayer.pause()
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
        DeviceSleepManager.shared.removeBlock(blockObject: sleepBlockObject)
        teardownRemoteCommandCenter()
    }

    private func endAudioActivities() {
        SUIEnvironment.shared.audioSessionRef.endAudioActivity(audioActivity)
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
        let cmTime = CMTimeMake(value: Int64(currentTime * Double(timescale)), timescale: timescale)
        audioPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)

        delegate?.setAudioProgress(self.currentTime, duration: self.duration, playbackRate: playbackRate)

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
            audioPlayer != nil,
            let backgroundPlaybackName = audioActivity.backgroundPlaybackName, !backgroundPlaybackName.isEmpty
        else {
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: backgroundPlaybackName,
            MPMediaItemPropertyPlaybackDuration: self.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: self.currentTime
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
        guard !SUIEnvironment.shared.audioSessionRef.wantsBackgroundPlayback else { return }

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Events

    private func audioPlayerUpdated(timer: Timer) {
        AssertIsOnMainThread()

        owsAssertDebug(audioPlayerPoller != nil)
        guard audioPlayer != nil else {
            owsFailDebug("audioPlayer == nil")
            return
        }

        delegate?.setAudioProgress(self.currentTime, duration: self.duration, playbackRate: playbackRate)
    }
}

extension AudioPlayer {

    @objc
    fileprivate func audioPlayerDidFinishPlaying() {
        AssertIsOnMainThread()

        stop()
        audioPlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)

        delegate?.audioPlayerDidFinish()

        if self.isLooping {
            self.play()
        }
    }
}
