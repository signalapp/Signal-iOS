//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
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
    private let sleepManager: DeviceSleepManager

    init(thread: TSThread, audioSession: AudioSession, sleepManager: DeviceSleepManager) {
        self.threadUniqueId = thread.uniqueId
        self.audioFileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: "m4a")
        self.audioActivity = AudioActivity(audioDescription: "Voice Message Recording", behavior: .playAndRecord)
        self.audioSession = audioSession
        self.sleepManager = sleepManager
    }

    private var audioRecorder: AVAudioRecorder? {
        didSet {
            guard oldValue !== audioRecorder else { return }
            if let oldValue {
                sleepManager.removeBlock(blockObject: oldValue)
            }
            if let audioRecorder {
                sleepManager.addBlock(blockObject: audioRecorder)
            }
        }
    }

    var isRecording: Bool { audioRecorder?.isRecording ?? false }

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
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 32000
                ]
            )
            self.audioRecorder = audioRecorder
        } catch {
            throw OWSAssertionError("Couldn't create audioRecorder: \(error)")
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

        guard let audioRecorder = audioRecorder else { return }
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

        guard let audioRecorder = audioRecorder else { return }
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

    func convertToDraft(transaction: SDSAnyWriteTransaction) -> VoiceMessageInterruptedDraft {
        let directoryUrl = VoiceMessageInterruptedDraftStore.saveDraft(
            audioFileUrl: audioFileUrl,
            threadUniqueId: threadUniqueId,
            transaction: transaction
        )
        return VoiceMessageInterruptedDraft(threadUniqueId: threadUniqueId, directoryUrl: directoryUrl)
    }

    func prepareForSending() throws -> URL {
        return audioFileUrl
    }
}
