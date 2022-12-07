//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

protocol CVAudioPlayerListener {
    func audioPlayerStateDidChange(attachmentId: String)
    func audioPlayerDidFinish(attachmentId: String)
    func audioPlayerDidMarkViewed(attachmentId: String)
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
//
// It's lifetime matches CVC.
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
    public typealias AttachmentId = String
    private var progressCache = LRUCache<AttachmentId, TimeInterval>(maxSize: 512)

    // Playback rate cached by thread id, _not_ attachment ID. Playback rate is preserved
    // across all audio attachments in a given thread.
    //
    // Note that the source of truth for playback rate is the ThreadAssociatedData db table,
    // but we keep this in-memory cache around for autoplay purposes.
    public typealias ThreadId = String
    private var playbackRateCache = LRUCache<ThreadId, Float>(maxSize: 512)

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

    private func ensurePlayback(for attachment: AudioAttachment, forAutoplay: Bool = false) -> CVAudioPlayback? {
        AssertIsOnMainThread()

        guard let attachmentId = attachment.attachmentStream?.uniqueId else {
            return nil
        }

        autoplayAttachmentId = forAutoplay ? attachmentId : nil

        if let audioPlayback = self.audioPlayback,
           audioPlayback.attachmentId == attachmentId {
            return audioPlayback
        }
        guard let audioPlayback = CVAudioPlayback(attachment: attachment) else {
            owsFailDebug("Could not play audio attachment.")
            return nil
        }
        // Restore playback continuity.
        if let progress = progressCache[attachmentId] {
            audioPlayback.setProgress(progress)
        }
        if
            let uniqueThreadId = audioPlayback.uniqueThreadId,
            let playbackRate = playbackRateCache[uniqueThreadId]
        {
            audioPlayback.setPlaybackRate(playbackRate)
        } else {
            audioPlayback.setPlaybackRate(1)
        }
        audioPlayback.delegate = self

        let oldAudioPlayback = self.audioPlayback
        self.audioPlayback = audioPlayback

        // Let the existing player know its state has changed.
        if let oldId = oldAudioPlayback?.attachmentId {
            for listener in listeners.elements {
                listener.audioPlayerStateDidChange(attachmentId: oldId)
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
                listener.audioPlayerDidMarkViewed(attachmentId: audioPlayback.attachmentId)
            }
        }

        audioPlayback.togglePlayState()
    }

    public var audioPlaybackState: AudioPlaybackState = .stopped
    private var soundPlayer: AudioPlayer?
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

    public func autoplayNextAudioAttachment(_ audioAttachment: AudioAttachment?) {
        AssertIsOnMainThread()

        guard let audioAttachment = audioAttachment, let attachmentStream = audioAttachment.attachmentStream else {
            if audioPlayback?.attachmentId == autoplayAttachmentId {
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

    public func setPlaybackProgress(progress: TimeInterval,
                                    forAttachmentStream attachmentStream: TSAttachmentStream) {
        AssertIsOnMainThread()

        progressCache[attachmentStream.uniqueId] = progress
        if let audioPlayback = audioPlayback, audioPlayback.attachmentId == attachmentStream.uniqueId {
            audioPlayback.setProgress(progress)
        }
    }

    public func playbackProgress(forAttachmentStream attachmentStream: TSAttachmentStream) -> TimeInterval {
        AssertIsOnMainThread()

        let attachmentId = attachmentStream.uniqueId
        return progressCache[attachmentId] ?? 0
    }

    public func setPlaybackRate(
        _ rate: Float,
        forThreadUniqueId threadId: ThreadId
    ) {
        AssertIsOnMainThread()

        // Cache it so if this gets called before playback begins and
        // we create the audioPlayback instance later, we can set the rate on it.
        playbackRateCache[threadId] = rate
        if
            let audioPlayback = audioPlayback,
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
}

extension CVAudioPlayer: AudioPlayerDelegate {
    public func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float) {}

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
// TODO: Should we combine this with AudioPlayer?
private class CVAudioPlayback: NSObject, AudioPlayerDelegate {

    fileprivate weak var delegate: CVAudioPlaybackDelegate?

    fileprivate let uniqueThreadId: String?
    fileprivate let attachmentId: String

    private let audioPlayer: AudioPlayer

    private let _playbackState = AtomicValue<AudioPlaybackState>(AudioPlaybackState.stopped)
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
        let playbackRate: Float

        static var unknown: AudioTiming {
            AudioTiming(progress: 0, duration: 0, playbackRate: 1)
        }
    }

    private let audioTiming = AtomicValue<AudioTiming>(AudioTiming.unknown)
    public var progress: TimeInterval {
        AssertIsOnMainThread()

        return audioTiming.get().progress
    }
    public var duration: TimeInterval {
        AssertIsOnMainThread()

        return audioTiming.get().duration
    }
    public var playbackRate: Float {
        AssertIsOnMainThread()

        return audioTiming.get().playbackRate
    }

    public func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float) {
        AssertIsOnMainThread()

        audioTiming.set(AudioTiming(progress: progress, duration: duration, playbackRate: playbackRate))

        delegate?.audioPlaybackStateDidChange(self)
    }

    public func audioPlayerDidFinish() {
        AssertIsOnMainThread()

        // Clear progress, preserve duration and playback rate.
        audioTiming.set(AudioTiming(progress: 0, duration: duration, playbackRate: playbackRate))

        delegate?.audioPlaybackDidFinish(self)
    }

    public required init?(attachment: AudioAttachment) {
        AssertIsOnMainThread()

        guard let attachmentStream = attachment.attachmentStream else {
            owsFailDebug("missing audio attachment stream \(attachment)")
            return nil
        }
        self.attachmentId = attachmentStream.uniqueId

        guard let mediaURL = attachmentStream.originalMediaURL else {
            owsFailDebug("mediaURL was unexpectedly nil for attachment: \(attachmentStream)")
            return nil
        }

        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            owsFailDebug("audio file missing at path: \(mediaURL)")
            return nil
        }

        audioPlayer = AudioPlayer(mediaUrl: mediaURL, audioBehavior: .audioMessagePlayback)
        uniqueThreadId = attachment.owningMessage?.uniqueThreadId

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

    public func setPlaybackRate(_ rate: Float) {
        AssertIsOnMainThread()

        audioPlayer.playbackRate = rate
    }
}
