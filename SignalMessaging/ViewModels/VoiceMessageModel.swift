//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

@objc
public class VoiceMessageModel: NSObject {
    public let threadUniqueId: String

    @objc
    public static let draftVoiceMessageDirectory = URL(
        fileURLWithPath: "draft-voice-messages",
        isDirectory: true,
        relativeTo: URL(
            fileURLWithPath: CurrentAppContext().appSharedDataDirectoryPath(),
            isDirectory: true
        )
    )

    @objc
    public init(thread: TSThread) {
        self.threadUniqueId = thread.uniqueId
    }

    // MARK: -

    private static var keyValueStore: SDSKeyValueStore { .init(collection: "DraftVoiceMessage") }

    @objc(hasDraftForThread:transaction:)
    public static func hasDraft(for thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        hasDraft(for: thread.uniqueId, transaction: transaction)
    }
    @objc(hasDraftForThreadUniqueId:transaction:)
    public static func hasDraft(for threadUniqueId: String, transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(threadUniqueId, defaultValue: false, transaction: transaction)
    }

    @objc
    public static func allDraftFilePaths(transaction: SDSAnyReadTransaction) -> Set<String> {
        return Set(keyValueStore.allKeys(transaction: transaction).compactMap { threadUniqueId in
            try? OWSFileSystem.recursiveFilesInDirectory(directory(for: threadUniqueId).path)
        }.reduce([], +))
    }

    @objc(clearDraftForThread:transaction:)
    public static func clearDraft(for thread: TSThread, transaction: SDSAnyWriteTransaction) {
        clearDraft(for: thread.uniqueId, transaction: transaction)
    }
    @objc(clearDraftForThreadUniqueId:transaction:)
    public static func clearDraft(for threadUniqueId: String, transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeValue(forKey: threadUniqueId, transaction: transaction)
        transaction.addAsyncCompletion {
            do {
                try OWSFileSystem.deleteFileIfExists(url: Self.directory(for: threadUniqueId))
            } catch {
                owsFailDebug("Failed to delete voice memo draft")
            }
        }
    }

    @objc
    public func saveDraft(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.setBool(true, key: threadUniqueId, transaction: transaction)
    }

    @objc
    public func clearDraft(transaction: SDSAnyWriteTransaction) {
        Self.clearDraft(for: threadUniqueId, transaction: transaction)
    }

    // MARK: -

    private static let audioExtension = "m4a"
    private static let audioUTI: String = kUTTypeMPEG4Audio as String

    @objc
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

    private static func directory(for threadUniqueId: String) -> URL {
        return URL(
            fileURLWithPath: threadUniqueId.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!,
            isDirectory: true,
            relativeTo: Self.draftVoiceMessageDirectory
        )
    }

    private var directory: URL {
        let directory = Self.directory(for: threadUniqueId)
        OWSFileSystem.ensureDirectoryExists(directory.path)
        return directory
    }

    public lazy var audioWaveform: AudioWaveform? =
        AudioWaveformManager.audioWaveform(forAudioPath: audioFile.path, waveformPath: waveformFile.path)

    public lazy var audioPlayer: OWSAudioPlayer =
        .init(mediaUrl: audioFile, audioBehavior: .audioMessagePlayback)

    private var audioFile: URL { URL(fileURLWithPath: "voice-memo.\(Self.audioExtension)", relativeTo: directory) }
    private var waveformFile: URL { URL(fileURLWithPath: "waveform.dat", relativeTo: directory) }
    private func outputFileName(at date: Date) -> String {
        String(
            format: "%@ %@.%@",
            NSLocalizedString("VOICE_MESSAGE_FILE_NAME", comment: "Filename for voice messages."),
            DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short),
            Self.audioExtension
        )
    }

    // MARK: -

    @objc
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
            throw OWSAssertionError("Could't cofigure audio session")
        }

        let audioRecorder: AVAudioRecorder
        do {
            audioRecorder = try AVAudioRecorder(
                url: audioFile,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128 * 1024
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
