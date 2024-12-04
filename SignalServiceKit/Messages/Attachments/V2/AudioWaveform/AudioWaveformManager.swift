//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AudioWaveformError: Error {
    case audioTooLong
    case fileIOError
    case invalidAudioFile
}

public protocol AudioWaveformManager {

    func audioWaveform(
        forAttachment attachment: AttachmentStream,
        highPriority: Bool
    ) -> Task<AudioWaveform, Error>

    func audioWaveform(
        forAudioPath audioPath: String,
        waveformPath: String
    ) -> Task<AudioWaveform, Error>

    func audioWaveform(
        forEncryptedAudioFileAtPath filePath: String,
        encryptionKey: Data,
        plaintextDataLength: UInt32,
        mimeType: String,
        outputWaveformPath: String
    ) async throws

    /// No caching, no enqueueing.
    /// Generates an audio waveform synchronously, blocking on file I/O operations.
    func audioWaveformSync(
        forAudioPath audioPath: String
    ) throws -> AudioWaveform

    /// No caching, no enqueueing.
    /// Generates an audio waveform synchronously, blocking on file I/O operations.
    func audioWaveformSync(
        forEncryptedAudioFileAtPath filePath: String,
        encryptionKey: Data,
        plaintextDataLength: UInt32,
        mimeType: String
    ) throws -> AudioWaveform
}
