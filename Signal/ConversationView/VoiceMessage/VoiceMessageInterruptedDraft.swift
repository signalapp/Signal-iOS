//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
import SignalServiceKit
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

    init(threadUniqueId: String, directoryUrl: URL) {
        self.threadUniqueId = threadUniqueId
        self.audioFileUrl = URL(fileURLWithPath: Constants.audioFilename, relativeTo: directoryUrl)
    }

    static func currentDraft(for thread: TSThread, transaction: DBReadTransaction) -> VoiceMessageInterruptedDraft? {
        let directoryUrl = VoiceMessageInterruptedDraftStore.directoryUrl(
            threadUniqueId: thread.uniqueId,
            transaction: transaction,
        )
        return directoryUrl.map { VoiceMessageInterruptedDraft(threadUniqueId: thread.uniqueId, directoryUrl: $0) }
    }

    // MARK: -

    func clearDraft(transaction: DBWriteTransaction) {
        VoiceMessageInterruptedDraftStore.clearDraft(for: threadUniqueId, transaction: transaction)
    }

    // MARK: -

    /// The waveform is used solely for UI, so it isn't sampled until something
    /// asks for it. The samples are then cached for the life of the draft.
    private(set) lazy var audioWaveformTask: Task<AudioWaveform, Error> = {
        let audioFilePath = self.audioFileUrl.path
        let threadUniqueId = self.threadUniqueId

        return Task {
            let audioWaveformManager = DependenciesBridge.shared.audioWaveformManager
            let db = SSKEnvironment.shared.databaseStorageRef

            let cachedSamples = db.read { tx in
                VoiceMessageInterruptedDraftStore.waveformSamples(
                    threadUniqueId: threadUniqueId,
                    transaction: tx,
                )
            }
            if let cachedSamples {
                return AudioWaveform(waveformData: cachedSamples)
            }

            let waveform = try audioWaveformManager.computeAudioWaveform(audioFilePath: audioFilePath)

            await db.awaitableWrite { tx in
                VoiceMessageInterruptedDraftStore.setWaveformSamples(
                    waveform.waveformData,
                    threadUniqueId: threadUniqueId,
                    transaction: tx,
                )
            }

            return waveform
        }
    }()

    private(set) lazy var audioPlayer: AudioPlayer = {
        AudioPlayer(decryptedFileUrl: audioFileUrl, audioBehavior: .audioMessagePlayback)
    }()

    private(set) lazy var duration: TimeInterval? = {
        guard OWSFileSystem.fileOrFolderExists(url: audioFileUrl) else { return nil }
        return try? AVAudioPlayer(
            contentsOf: audioFileUrl,
        ).duration
    }()

    // MARK: -

    func prepareForSending() throws -> URL {
        let temporaryAudioFileUrl = OWSFileSystem.temporaryFileUrl(
            fileName: audioFileUrl.lastPathComponent,
            isAvailableWhileDeviceLocked: false,
        )
        try FileManager.default.copyItem(at: audioFileUrl, to: temporaryAudioFileUrl)
        return temporaryAudioFileUrl
    }
}
