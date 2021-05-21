//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol CVAudioPlayerListener {
    func audioPlayerStateDidChange(attachmentId: String)
    func audioPlayerDidFinish(attachmentId: String)
    func audioPlayerDidMarkViewed(attachmentId: String)
}

// MARK: -

// Tool for playing audio attachments and observing playback state.
//
// Responsibilites:
//
// * Ensure that no more than one audio attachment is playing at a time.
// * Ensure playback continuity.
//   * This should work:
//     * If cells are reloaded
//     * Playback is manipulated in a subview like message details view
//     * The cell is scrolled offscreen and unloaded.
//     * etc.
// * Ensure thread safety.
//
// It's lifetime matches CVC.
@objc
public class CVAudioPlayer: NSObject {

    // The currently playing audio, if any.
    private var _audioPlayback: CVAudioPlayback?
    private var audioPlayback: CVAudioPlayback? {
        get {
            AssertIsOnMainThread()

            return _audioPlayback
        }
        set {
            AssertIsOnMainThread()

            _audioPlayback = newValue
        }
    }

    private var autoplayAttachmentId: String?

    // Views need to update to reflect playback progress, state changes.
    private var listeners = WeakArray<CVAudioPlayerListener>()

    func addListener(_ listener: CVAudioPlayerListener) {
        AssertIsOnMainThread()

        listeners.append(listener)
        listeners.cullExpired()
    }

    // This ensures playback continuity. If users switches between
    // playing back different audio attachment, each should resume
    // where it left off.
    //
    // Playback progress should be continuous even if the corresponding
    // cells are reloaded or scrolled offscreen and unloaded.
    private var progressCache = [String: TimeInterval]()

    public func audioPlaybackState(forAttachmentId attachmentId: String) -> AudioPlaybackState {
        AssertIsOnMainThread()

        guard let audioPlayback = audioPlayback else {
            return .stopped
        }
        guard audioPlayback.attachmentId == attachmentId else {
            return .stopped
        }
        return audioPlayback.audioPlaybackState
    }

    private func ensurePlayback(forAttachmentStream attachmentStream: TSAttachmentStream, forAutoplay: Bool = false) -> CVAudioPlayback? {
        AssertIsOnMainThread()

        autoplayAttachmentId = forAutoplay ? attachmentStream.uniqueId : nil

        let attachmentId = attachmentStream.uniqueId
        if let audioPlayback = self.audioPlayback,
           audioPlayback.attachmentId == attachmentId {
            return audioPlayback
        }
        guard let audioPlayback = CVAudioPlayback(attachmentStream: attachmentStream) else {
            owsFailDebug("Could not play audio attachment.")
            return nil
        }
        // Restore playback continuity.
        if let progress = progressCache[attachmentId] {
            audioPlayback.setProgress(progress)
        }
        audioPlayback.delegate = self
        self.audioPlayback = audioPlayback
        return audioPlayback
    }

    @objc
    public func togglePlayState(forAudioAttachment audioAttachment: AudioAttachment) {
        AssertIsOnMainThread()

        guard let attachmentStream = audioAttachment.attachmentStream else { return }

        guard let audioPlayback = ensurePlayback(forAttachmentStream: attachmentStream) else {
            owsFailDebug("Could not play audio attachment.")
            return
        }

        if audioAttachment.markOwningMessageAsViewed() {
            for listener in listeners.elements {
                listener.audioPlayerDidMarkViewed(attachmentId: audioPlayback.attachmentId)
            }
        }

        audioPlayback.togglePlayState()
    }

    public var audioPlaybackState: AudioPlaybackState = .stopped
    private var soundPlayer: OWSAudioPlayer?
    private var soundComplete: (() -> Void)?
    private func playStandardSound(_ sound: OWSStandardSound, completion: (() -> Void)? = nil) {
        AssertIsOnMainThread()

        if let soundPlayer = soundPlayer {
            soundPlayer.stop()
            soundComplete?()
        }

        soundPlayer = OWSSounds.audioPlayer(forSound: sound.rawValue, audioBehavior: .audioMessagePlayback)
        soundPlayer?.delegate = self
        soundPlayer?.play()
        soundComplete = completion
    }

    @objc
    public func autoplayNextAudioAttachment(_ audioAttachment: AudioAttachment?) {
        AssertIsOnMainThread()

        guard let audioAttachment = audioAttachment, let attachmentStream = audioAttachment.attachmentStream else {
            if audioPlayback?.attachmentId == autoplayAttachmentId {
                // Play a tone indicating the last track completed.
                playStandardSound(.endLastTrack)
            }
            return
        }

        guard let audioPlayback = ensurePlayback(forAttachmentStream: attachmentStream, forAutoplay: true) else {
            owsFailDebug("Could not play audio attachment.")
            return
        }

        // Play a tone indicating the next track is starting.
        playStandardSound(.beginNextTrack) { [weak self] in
            // Make sure the user didn't start another attachment while the tone was playing.
            guard self?.autoplayAttachmentId == attachmentStream.uniqueId else { return }
            guard self?.audioPlayback?.attachmentId == attachmentStream.uniqueId else { return }
            guard audioPlayback.audioPlaybackState != .playing else { return }

            if audioAttachment.markOwningMessageAsViewed() {
                for listener in self?.listeners.elements ?? [] {
                    listener.audioPlayerDidMarkViewed(attachmentId: audioPlayback.attachmentId)
                }
            }

            audioPlayback.setProgress(0)
            audioPlayback.togglePlayState()
        }
    }

    @objc
    public func setPlaybackProgress(progress: TimeInterval,
                                    forAttachmentStream attachmentStream: TSAttachmentStream) {
        AssertIsOnMainThread()

        progressCache[attachmentStream.uniqueId] = progress
        if let audioPlayback = audioPlayback, audioPlayback.attachmentId == attachmentStream.uniqueId {
            audioPlayback.setProgress(progress)
        }
    }

    @objc
    public func playbackProgress(forAttachmentStream attachmentStream: TSAttachmentStream) -> TimeInterval {
        AssertIsOnMainThread()

        let attachmentId = attachmentStream.uniqueId
        guard let progress = progressCache[attachmentId] else {
            return 0
        }
        return progress
    }

    @objc
    public func stopAll() {
        guard let audioPlayback = self.audioPlayback else {
            return
        }
        audioPlayback.stop()
        self.audioPlayback = nil
    }
}

extension CVAudioPlayer: OWSAudioPlayerDelegate {
    public func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval) {}

    public func audioPlayerDidFinish() {
        DispatchMainThreadSafe { [weak self] in
            self?.soundPlayer?.stop()
            self?.soundPlayer = nil

            self?.soundComplete?()
            self?.soundComplete = nil
        }
    }
}

// MARK: -

extension CVAudioPlayer: CVAudioPlaybackDelegate {
    fileprivate func audioPlaybackStateDidChange(_ audioPlayback: CVAudioPlayback) {
        AssertIsOnMainThread()

        switch audioPlayback.audioPlaybackState {
        case .playing:
            if audioPlayback != self.audioPlayback { audioPlayback.togglePlayState() }
            progressCache[audioPlayback.attachmentId] = audioPlayback.progress
        case .stopped:
            progressCache[audioPlayback.attachmentId] = 0
        case .paused:
            break
        }

        for listener in listeners.elements {
            listener.audioPlayerStateDidChange(attachmentId: audioPlayback.attachmentId)
        }
    }

    fileprivate func audioPlaybackDidFinish(_ audioPlayback: CVAudioPlayback) {
        AssertIsOnMainThread()

        progressCache[audioPlayback.attachmentId] = 0

        for listener in listeners.elements {
            listener.audioPlayerDidFinish(attachmentId: audioPlayback.attachmentId)
        }
    }
}

// MARK: -

private protocol CVAudioPlaybackDelegate: AnyObject {
    func audioPlaybackStateDidChange(_ audioPlayback: CVAudioPlayback)
    func audioPlaybackDidFinish(_ audioPlayback: CVAudioPlayback)
}

// MARK: -

// Used for playback of a given audio attachment.
//
// TODO: Should we combine this with OWSAudioPlayer?
private class CVAudioPlayback: NSObject, OWSAudioPlayerDelegate {

    fileprivate weak var delegate: CVAudioPlaybackDelegate?

    fileprivate let attachmentId: String

    private let audioPlayer: OWSAudioPlayer

    private let _playbackState = AtomicValue<AudioPlaybackState>(AudioPlaybackState.stopped)
    @objc
    public var audioPlaybackState: AudioPlaybackState {
        get {
            AssertIsOnMainThread()

            return _playbackState.get()
        }
        set {
            AssertIsOnMainThread()

            _playbackState.set(newValue)
        }
    }

    private struct AudioTiming {
        let progress: TimeInterval
        let duration: TimeInterval

        static var unknown: AudioTiming {
            AudioTiming(progress: 0, duration: 0)
        }
    }

    private let audioTiming = AtomicValue<AudioTiming>(AudioTiming.unknown)
    @objc
    public var progress: TimeInterval {
        AssertIsOnMainThread()

        return audioTiming.get().progress
    }
    @objc
    public var duration: TimeInterval {
        AssertIsOnMainThread()

        return audioTiming.get().duration
    }

    @objc
    public func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval) {
        AssertIsOnMainThread()

        audioTiming.set(AudioTiming(progress: progress, duration: duration))

        delegate?.audioPlaybackStateDidChange(self)
    }

    @objc
    public func audioPlayerDidFinish() {
        AssertIsOnMainThread()

        // Clear progress, preserve duration.
        audioTiming.set(AudioTiming(progress: 0, duration: duration))

        delegate?.audioPlaybackDidFinish(self)
    }

    @objc
    public required init?(attachmentStream: TSAttachmentStream) {
        AssertIsOnMainThread()

        self.attachmentId = attachmentStream.uniqueId

        guard let mediaURL = attachmentStream.originalMediaURL else {
            owsFailDebug("mediaURL was unexpectedly nil for attachment: \(attachmentStream)")
            return nil
        }

        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            owsFailDebug("audio file missing at path: \(mediaURL)")
            return nil
        }

        audioPlayer = OWSAudioPlayer(mediaUrl: mediaURL, audioBehavior: .audioMessagePlayback)

        super.init()

        audioPlayer.delegate = self
        audioPlayer.setupAudioPlayer()
    }

    deinit {
        stop()
    }

    fileprivate func stop() {
        AssertIsOnMainThread()

        audioPlayer.stop()
    }

    public func togglePlayState() {
        AssertIsOnMainThread()

        audioPlayer.togglePlayState()
    }

    public func setProgress(_ time: TimeInterval) {
        AssertIsOnMainThread()

        audioPlayer.setCurrentTime(time)
    }
}
