//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
public import SignalServiceKit
public import SignalUI

/// Identifies playback of one attachment on one message. The same attachment
/// can belong to multiple messages, such as a forwarded voice note, and each
/// is played back independently.
public struct CVAudioPlaybackID: Hashable {
    public let attachmentID: Attachment.IDType
    public let interactionID: String

    public init(audioAttachment: AudioAttachment) {
        self.attachmentID = audioAttachment.attachment.id
        self.interactionID = audioAttachment.owningMessage.uniqueId
    }
}

// MARK: -

protocol CVAudioPlayerListener {
    func audioPlayerStateDidChange(playbackID: CVAudioPlaybackID)
    func audioPlayerDidFinish(playbackID: CVAudioPlaybackID)
    func audioPlayerDidMarkViewed(playbackID: CVAudioPlaybackID)
}

// MARK: -

// Tool for playing audio attachments and observing playback state.
//
// Responsibilities:
//
// * Ensure that no more than one audio attachment is playing at a time.
// * Ensure playback continuity.
//   * This should work:
//     * If cells are reloaded
//     * Playback is manipulated in a subview like message details view
//     * The cell is scrolled offscreen and unloaded.
//     * etc.
// * Ensure thread safety.
public class CVAudioPlayer: NSObject, AudioPlayerDelegate, CVAudioPlaybackDelegate {
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

    private var autoplayPlaybackID: CVAudioPlaybackID?

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
    private var progressCache = LRUCache<CVAudioPlaybackID, TimeInterval>(maxSize: 512)

    // Playback rate cached by thread id, _not_ attachment ID. Playback rate is preserved
    // across all audio attachments in a given thread.
    //
    // Note that the source of truth for playback rate is the ThreadAssociatedData db table,
    // but we keep this in-memory cache around for autoplay purposes.
    public typealias ThreadId = String
    private var playbackRateCache = LRUCache<ThreadId, Float>(maxSize: 512)

    // If nil, autoplay is enabled. Otherwise, this closure returns whether to play the next audio attachement. It's
    // called when the current attachment finishes playing.
    var shouldAutoplayNextAudioAttachment: (() -> Bool)?

    public func audioPlaybackState(playbackID: CVAudioPlaybackID) -> AudioPlaybackState {
        AssertIsOnMainThread()

        guard let audioPlayback, audioPlayback.playbackID == playbackID else {
            return .stopped
        }
        return audioPlayback.audioPlaybackState
    }

    private func ensurePlayback(for audioAttachment: AudioAttachment, forAutoplay: Bool = false) -> CVAudioPlayback? {
        AssertIsOnMainThread()

        guard let referencedAttachmentStream = audioAttachment.attachmentStream else {
            return nil
        }

        let playbackID = CVAudioPlaybackID(audioAttachment: audioAttachment)
        autoplayPlaybackID = forAutoplay ? playbackID : nil

        if
            let audioPlayback = self.audioPlayback,
            audioPlayback.playbackID == playbackID
        {
            return audioPlayback
        }

        let audioPlayback = CVAudioPlayback(
            audioAttachment: audioAttachment,
            attachmentStream: referencedAttachmentStream.attachmentStream,
        )

        // Restore playback continuity.
        if let progress = progressCache[audioPlayback.playbackID] {
            audioPlayback.setProgress(progress)
        }
        if let playbackRate = playbackRateCache[audioPlayback.uniqueThreadId] {
            audioPlayback.setPlaybackRate(playbackRate)
        } else {
            audioPlayback.setPlaybackRate(1)
        }
        audioPlayback.delegate = self

        let oldAudioPlayback = self.audioPlayback
        self.audioPlayback = audioPlayback

        // Let the existing player know its state has changed.
        if let oldAudioPlayback {
            for listener in listeners.elements {
                listener.audioPlayerStateDidChange(playbackID: oldAudioPlayback.playbackID)
            }
        }

        return audioPlayback
    }

    public func togglePlayState(forAudioAttachment audioAttachment: AudioAttachment) {
        AssertIsOnMainThread()

        guard let audioPlayback = ensurePlayback(for: audioAttachment) else {
            owsFailDebug("Could not play audio attachment.")
            return
        }

        if audioAttachment.markOwningMessageAsViewed() {
            for listener in listeners.elements {
                listener.audioPlayerDidMarkViewed(playbackID: audioPlayback.playbackID)
            }
        }

        audioPlayback.togglePlayState()
    }

    public var audioPlaybackState: AudioPlaybackState = .stopped
    private var soundPlayer: AudioPlayer?
    private var soundComplete: (() -> Void)?
    private func playStandardSound(_ sound: StandardSound, completion: (() -> Void)? = nil) {
        AssertIsOnMainThread()

        if let soundPlayer {
            soundPlayer.stop()
            soundComplete?()
        }

        soundPlayer = Sounds.audioPlayer(forSound: .standard(sound), audioBehavior: .audioMessagePlayback)
        soundPlayer?.delegate = self
        soundPlayer?.play()
        soundComplete = completion
    }

    public func autoplayNextAudioAttachmentIfNeeded(_ audioAttachment: AudioAttachment?) {
        AssertIsOnMainThread()

        guard shouldAutoplayNextAudioAttachment?() ?? true else {
            playStandardSound(.endLastTrack)
            return
        }

        guard let audioAttachment, audioAttachment.attachmentStream != nil else {
            if audioPlayback?.playbackID == autoplayPlaybackID {
                // Play a tone indicating the last track completed.
                playStandardSound(.endLastTrack)
            }
            return
        }

        guard let audioPlayback = ensurePlayback(for: audioAttachment, forAutoplay: true) else {
            owsFailDebug("Could not play audio attachment.")
            return
        }

        // Play a tone indicating the next track is starting.
        playStandardSound(.beginNextTrack) { [weak self] in
            // Make sure the user didn't start another attachment while the tone was playing.
            guard self?.autoplayPlaybackID == audioPlayback.playbackID else { return }
            guard self?.audioPlayback === audioPlayback else { return }
            guard audioPlayback.audioPlaybackState != .playing else { return }

            if audioAttachment.markOwningMessageAsViewed() {
                for listener in self?.listeners.elements ?? [] {
                    listener.audioPlayerDidMarkViewed(playbackID: audioPlayback.playbackID)
                }
            }

            audioPlayback.setProgress(0)
            audioPlayback.togglePlayState()
        }
    }

    public func setPlaybackProgress(_ progress: TimeInterval, playbackID: CVAudioPlaybackID) {
        AssertIsOnMainThread()

        progressCache[playbackID] = progress
        if let audioPlayback, audioPlayback.playbackID == playbackID {
            audioPlayback.setProgress(progress)
        }
    }

    public func playbackProgress(playbackID: CVAudioPlaybackID) -> TimeInterval {
        AssertIsOnMainThread()

        return progressCache[playbackID] ?? 0
    }

    public func setPlaybackRate(
        _ rate: Float,
        forThreadUniqueId threadId: ThreadId,
    ) {
        AssertIsOnMainThread()

        // Cache it so if this gets called before playback begins and
        // we create the audioPlayback instance later, we can set the rate on it.
        playbackRateCache[threadId] = rate
        if
            let audioPlayback,
            audioPlayback.uniqueThreadId == threadId
        {
            audioPlayback.setPlaybackRate(rate)
        }
    }

    public func stopAll() {
        guard let audioPlayback = self.audioPlayback else {
            return
        }
        audioPlayback.stop()
        self.audioPlayback = nil
    }

    // MARK: - AudioPlayerDelegate

    public func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float) {}

    public func audioPlayerDidFinish() {
        DispatchMainThreadSafe { [weak self] in
            self?.soundPlayer?.stop()
            self?.soundPlayer = nil

            self?.soundComplete?()
            self?.soundComplete = nil
        }
    }

    // MARK: - CVAudioPlaybackDelegate

    fileprivate func audioPlaybackStateDidChange(_ audioPlayback: CVAudioPlayback) {
        AssertIsOnMainThread()

        switch audioPlayback.audioPlaybackState {
        case .playing:
            if audioPlayback != self.audioPlayback { audioPlayback.togglePlayState() }
            progressCache[audioPlayback.playbackID] = audioPlayback.progress
        case .stopped:
            progressCache[audioPlayback.playbackID] = 0
        case .paused:
            break
        }

        for listener in listeners.elements {
            listener.audioPlayerStateDidChange(playbackID: audioPlayback.playbackID)
        }
    }

    fileprivate func audioPlaybackDidFinish(_ audioPlayback: CVAudioPlayback) {
        AssertIsOnMainThread()

        progressCache[audioPlayback.playbackID] = 0

        for listener in listeners.elements {
            listener.audioPlayerDidFinish(playbackID: audioPlayback.playbackID)
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
// TODO: Should we combine this with AudioPlayer?
private class CVAudioPlayback: NSObject, AudioPlayerDelegate {

    weak var delegate: CVAudioPlaybackDelegate?

    let uniqueThreadId: String
    let playbackID: CVAudioPlaybackID

    private let audioPlayer: AudioPlayer

    private let _playbackState = AtomicValue<AudioPlaybackState>(AudioPlaybackState.stopped, lock: .sharedGlobal)
    var audioPlaybackState: AudioPlaybackState {
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
        let playbackRate: Float

        static var unknown: AudioTiming {
            AudioTiming(progress: 0, duration: 0, playbackRate: 1)
        }
    }

    private let audioTiming = AtomicValue<AudioTiming>(AudioTiming.unknown, lock: .sharedGlobal)
    var progress: TimeInterval {
        AssertIsOnMainThread()

        return audioTiming.get().progress
    }

    var duration: TimeInterval {
        AssertIsOnMainThread()

        return audioTiming.get().duration
    }

    var playbackRate: Float {
        AssertIsOnMainThread()

        return audioTiming.get().playbackRate
    }

    func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float) {
        AssertIsOnMainThread()

        audioTiming.set(AudioTiming(progress: progress, duration: duration, playbackRate: playbackRate))

        delegate?.audioPlaybackStateDidChange(self)
    }

    func audioPlayerDidFinish() {
        AssertIsOnMainThread()

        // Clear progress, preserve duration and playback rate.
        audioTiming.set(AudioTiming(progress: 0, duration: duration, playbackRate: playbackRate))

        delegate?.audioPlaybackDidFinish(self)
    }

    init(
        audioAttachment: AudioAttachment,
        attachmentStream: AttachmentStream,
    ) {
        AssertIsOnMainThread()

        playbackID = CVAudioPlaybackID(audioAttachment: audioAttachment)
        audioPlayer = AudioPlayer(attachment: attachmentStream, audioBehavior: .audioMessagePlayback)
        uniqueThreadId = audioAttachment.owningMessage.uniqueThreadId

        super.init()

        audioPlayer.delegate = self
        audioPlayer.setupAudioPlayer()
    }

    deinit {
        stop()
    }

    func stop() {
        AssertIsOnMainThread()

        audioPlayer.stop()
    }

    func togglePlayState() {
        AssertIsOnMainThread()

        audioPlayer.togglePlayState()
    }

    func setProgress(_ time: TimeInterval) {
        AssertIsOnMainThread()

        audioPlayer.setCurrentTime(time)
    }

    func setPlaybackRate(_ rate: Float) {
        AssertIsOnMainThread()

        audioPlayer.playbackRate = rate
    }
}
