//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

/// Represents a voice note that was "interrupted" while being recorded.
///
/// An interrupted voice note will appear in the compose box, and it will
/// offer you a choice to play, delete, and/or send the voice note.
///
/// The easiest way to interrupt a recording is to use the "lock" mechanism
/// and then tap the back button in a chat. The voice note feature itself
/// doesn't expose a "stop recording but don't send" mechanism -- you either
/// cancel the recording or send the message.
///
/// This class works in tandem with ``VoiceMessageInProgressDraft``.
final class VoiceMessageInterruptedDraft: VoiceMessageSendableDraft {
    typealias Constants = VoiceMessageInterruptedDraftStore.Constants

    private let threadUniqueId: String
    private let audioFileUrl: URL
    private let waveformFileUrl: URL

    init(threadUniqueId: String, directoryUrl: URL) {
        self.threadUniqueId = threadUniqueId
        self.audioFileUrl = URL(fileURLWithPath: Constants.audioFilename, relativeTo: directoryUrl)
        self.waveformFileUrl = URL(fileURLWithPath: Constants.waveformFilename, relativeTo: directoryUrl)
    }

    public static func currentDraft(for thread: TSThread, transaction: SDSAnyReadTransaction) -> VoiceMessageInterruptedDraft? {
        let directoryUrl = VoiceMessageInterruptedDraftStore.directoryUrl(
            threadUniqueId: thread.uniqueId,
            transaction: transaction
        )
        return directoryUrl.map { VoiceMessageInterruptedDraft(threadUniqueId: thread.uniqueId, directoryUrl: $0) }
    }

    // MARK: -

    func clearDraft(transaction: SDSAnyWriteTransaction) {
        VoiceMessageInterruptedDraftStore.clearDraft(for: threadUniqueId, transaction: transaction)
    }

    // MARK: -

    public private(set) lazy var audioWaveform: AudioWaveform? = {
        // The file at `waveformPath` is created lazily by accessing this property.
        // It's used solely for UI and thus isn't created until it's needed.
        AudioWaveformManager.audioWaveform(forAudioPath: audioFileUrl.path, waveformPath: waveformFileUrl.path)
    }()

    public private(set) lazy var audioPlayer: AudioPlayer = {
        AudioPlayer(mediaUrl: audioFileUrl, audioBehavior: .audioMessagePlayback)
    }()

    public private(set) lazy var duration: TimeInterval? = {
        guard OWSFileSystem.fileOrFolderExists(url: audioFileUrl) else { return nil }
        audioPlayer.setupAudioPlayer()
        return audioPlayer.duration
    }()

    // MARK: -

    public func prepareForSending() throws -> URL {
        let temporaryAudioFileUrl = OWSFileSystem.temporaryFileUrl()
        try FileManager.default.copyItem(at: audioFileUrl, to: temporaryAudioFileUrl)
        return temporaryAudioFileUrl
    }
}
