//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit
import SignalUI

/// Represents a voice note that's actively being recorded.
///
/// In most cases you'll immediately send (or discard) voice notes you
/// record. When this happens, an instance of this type will be passed to
/// the voice note sending logic.
///
/// In some cases, an external event may interrupt an active recording. When
/// that happens, we convert this object into a durable
/// ``VoiceMessageInterruptedDraft``. That draft is visible in the compose
/// box for the user to return to later.
final class VoiceMessageInProgressDraft: VoiceMessageSendableDraft {
    private let threadUniqueId: String
    private let audioFileUrl: URL
    private let audioActivity: AudioActivity
    private let audioSession: AudioSession
    private let sleepManager: any DeviceSleepManager
    private let recordingFormat: VoiceMessageRecordingFormat

    init(
        thread: TSThread,
        audioSession: AudioSession,
        sleepManager: any DeviceSleepManager,
        recordingFormat: VoiceMessageRecordingFormat = .m4a,
    ) {
        self.threadUniqueId = thread.uniqueId
        self.audioFileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: recordingFormat.fileExtension)
        self.audioActivity = AudioActivity(audioDescription: "Voice Message Recording", behavior: .playAndRecord)
        self.audioSession = audioSession
        self.sleepManager = sleepManager
        self.recordingFormat = recordingFormat
    }

    deinit {
        Task { [sleepManager, sleepBlockObject] in
            await sleepManager.removeBlock(blockObject: sleepBlockObject)
        }
    }

    private let sleepBlockObject = DeviceSleepBlockObject(blockReason: "voice message")

    private var audioRecorder: AVAudioRecorder?

    var isRecording: Bool { audioRecorder?.isRecording ?? false }

    var voiceMessageRecordingFormat: VoiceMessageRecordingFormat { recordingFormat }

    func startRecording() throws {
        AssertIsOnMainThread()

        guard !isRecording else {
            throw OWSAssertionError("Attempted to start recording while recording is in progress")
        }

        guard audioSession.startAudioActivity(audioActivity) else {
            throw OWSAssertionError("Couldn't configure audio session")
        }

        let audioRecorder: AVAudioRecorder
        do {
            audioRecorder = try AVAudioRecorder(
                url: audioFileUrl,
                settings: recordingFormat.recorderSettings,
            )
            self.audioRecorder = audioRecorder
        } catch {
            throw OWSAssertionError("Couldn't create audioRecorder: \(error)")
        }

        MainActor.assumeIsolated {
            sleepManager.addBlock(blockObject: sleepBlockObject)
        }

        audioRecorder.isMeteringEnabled = true

        guard audioRecorder.prepareToRecord() else {
            throw OWSAssertionError("audioRecorder couldn't prepareToRecord.")
        }

        guard audioRecorder.record() else {
            throw OWSAssertionError("audioRecorder couldn't record.")
        }
    }

    func stopRecording() {
        AssertIsOnMainThread()

        MainActor.assumeIsolated {
            sleepManager.removeBlock(blockObject: sleepBlockObject)
        }

        guard let audioRecorder else { return }
        self.audioRecorder = nil

        self.duration = audioRecorder.currentTime

        audioRecorder.stop()

        // This is expensive. We can safely do it in the background.
        DispatchQueue.sharedUserInteractive.async {
            self.audioSession.endAudioActivity(self.audioActivity)
        }
    }

    func stopRecordingAsync() {
        AssertIsOnMainThread()

        MainActor.assumeIsolated {
            sleepManager.removeBlock(blockObject: sleepBlockObject)
        }

        guard let audioRecorder else { return }
        self.audioRecorder = nil

        self.duration = audioRecorder.currentTime

        // This is expensive. We can safely do it in the background
        // if we're not relying on the recorded audio (e.g. we canceled)
        DispatchQueue.sharedUserInteractive.async {
            audioRecorder.stop()
            self.audioSession.endAudioActivity(self.audioActivity)
        }
    }

    private(set) var duration: TimeInterval?

    func convertToDraft(transaction: DBWriteTransaction) -> VoiceMessageInterruptedDraft {
        let audioFilename = recordingFormat == .wav
            ? VoiceMessageInterruptedDraftStore.Constants.wavAudioFilename
            : VoiceMessageInterruptedDraftStore.Constants.audioFilename
        let directoryUrl = VoiceMessageInterruptedDraftStore.saveDraft(
            audioFileUrl: audioFileUrl,
            threadUniqueId: threadUniqueId,
            transaction: transaction,
            audioFilename: audioFilename,
        )
        if recordingFormat != .m4a {
            VoiceMessageInterruptedDraft.storeRecordingFormat(
                recordingFormat,
                in: directoryUrl,
            )
        }
        return VoiceMessageInterruptedDraft(threadUniqueId: threadUniqueId, directoryUrl: directoryUrl)
    }

    func prepareForSending() throws -> URL {
        return audioFileUrl
    }
}
