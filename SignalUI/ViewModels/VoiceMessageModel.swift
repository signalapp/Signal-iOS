//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import CoreServices
import SignalMessaging

public class VoiceMessageModel: NSObject {
    public let threadUniqueId: String

    private static var draftVoiceMessageDirectory: URL { VoiceMessageModels.draftVoiceMessageDirectory }

    public init(thread: TSThread) {
        self.threadUniqueId = thread.uniqueId
    }

    // MARK: -

    private static let audioExtension = "m4a"
    private static let audioUTI: String = kUTTypeMPEG4Audio as String

    public func prepareForSending() throws -> SignalAttachment {
        guard !isRecording else {
            throw OWSAssertionError("Can't send while actively recording")
        }

        guard OWSFileSystem.fileOrFolderExists(url: audioFile) else {
            throw OWSAssertionError("Missing audio file")
        }

        let temporaryDirectory = URL(fileURLWithPath: OWSTemporaryDirectory(), isDirectory: true)
        let temporaryAudioFile = URL(fileURLWithPath: audioFile.lastPathComponent, relativeTo: temporaryDirectory)
        try FileManager.default.copyItem(at: audioFile, to: temporaryAudioFile)

        let dataSource = try DataSourcePath.dataSource(with: temporaryAudioFile, shouldDeleteOnDeallocation: true)
        dataSource.sourceFilename = outputFileName(at: Date())

        let attachment = SignalAttachment.voiceMessageAttachment(dataSource: dataSource, dataUTI: Self.audioUTI)
        guard !attachment.hasError else {
            throw OWSAssertionError("Failed to create voice message attachment: \(attachment.errorName ?? "Unknown Error")")
        }

        return attachment
    }

    // MARK: -

    public func saveDraft(transaction: SDSAnyWriteTransaction) {
        VoiceMessageModels.saveDraft(threadUniqueId: threadUniqueId, transaction: transaction)
    }

    public func clearDraft(transaction: SDSAnyWriteTransaction) {
        VoiceMessageModels.clearDraft(for: threadUniqueId, transaction: transaction)
    }

    // MARK: -

    private var directory: URL {
        let directory = VoiceMessageModels.directory(for: threadUniqueId)
        OWSFileSystem.ensureDirectoryExists(directory.path)
        return directory
    }

    public lazy var audioWaveform: AudioWaveform? =
        AudioWaveformManager.audioWaveform(forAudioPath: audioFile.path, waveformPath: waveformFile.path)

    public lazy var audioPlayer: AudioPlayer =
        .init(mediaUrl: audioFile, audioBehavior: .audioMessagePlayback)

    private var audioFile: URL { URL(fileURLWithPath: "voice-memo.\(Self.audioExtension)", relativeTo: directory) }
    private var waveformFile: URL { URL(fileURLWithPath: "waveform.dat", relativeTo: directory) }
    private func outputFileName(at date: Date) -> String {
        String(
            format: "%@ %@.%@",
            OWSLocalizedString("VOICE_MESSAGE_FILE_NAME", comment: "Filename for voice messages."),
            DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short),
            Self.audioExtension
        )
    }

    // MARK: -

    public var isRecording: Bool { audioRecorder?.isRecording ?? false }

    public lazy var duration: TimeInterval? = {
        guard OWSFileSystem.fileOrFolderExists(url: audioFile) else { return nil }
        audioPlayer.setupAudioPlayer()
        return audioPlayer.duration
    }()

    private var audioRecorder: AVAudioRecorder? {
        didSet {
            guard oldValue != audioRecorder else { return }
            if let oldValue = oldValue {
                DeviceSleepManager.shared.removeBlock(blockObject: oldValue)
            }
            if let audioRecorder = audioRecorder {
                DeviceSleepManager.shared.addBlock(blockObject: audioRecorder)
            }
        }
    }

    private lazy var audioActivity = AudioActivity(audioDescription: "Voice Message Recording", behavior: .playAndRecord)

    public func startRecording() throws {
        AssertIsOnMainThread()

        guard !isRecording else {
            throw OWSAssertionError("Attempted to start recording while recording is in progress")
        }

        OWSFileSystem.deleteContents(ofDirectory: directory.path)

        guard audioSession.startAudioActivity(audioActivity) else {
            throw OWSAssertionError("Couldn't configure audio session")
        }

        let audioRecorder: AVAudioRecorder
        do {
            audioRecorder = try AVAudioRecorder(
                url: audioFile,
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

    public func stopRecording() {
        AssertIsOnMainThread()

        guard let audioRecorder = audioRecorder else { return }

        self.duration = audioRecorder.currentTime

        audioRecorder.stop()

        self.audioRecorder = nil

        // This is expensive. We can safely do it in the background.
        DispatchQueue.sharedUserInteractive.async {
            self.audioSession.endAudioActivity(self.audioActivity)
        }
    }

    public func stopRecordingAsync() {
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
}
