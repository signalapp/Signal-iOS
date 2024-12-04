//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class AudioWaveformManagerMock: AudioWaveformManager {

    public init() {}

    public func audioWaveform(forAttachment attachment: AttachmentStream, highPriority: Bool) -> Task<AudioWaveform, Error> {
        return Task {
            return AudioWaveform(decibelSamples: [])
        }
    }

    public func audioWaveform(forAudioPath audioPath: String, waveformPath: String) -> Task<AudioWaveform, Error> {
        return Task {
            return AudioWaveform(decibelSamples: [])
        }
    }

    public func audioWaveform(
        forEncryptedAudioFileAtPath filePath: String,
        encryptionKey: Data,
        plaintextDataLength: UInt32,
        mimeType: String,
        outputWaveformPath: String
    ) async throws {
        // Do nothing
    }

    public func audioWaveformSync(
        forAudioPath audioPath: String
    ) throws -> AudioWaveform {
        return AudioWaveform(decibelSamples: [])
    }

    public func audioWaveformSync(
        forEncryptedAudioFileAtPath filePath: String,
        encryptionKey: Data,
        plaintextDataLength: UInt32,
        mimeType: String
    ) throws -> AudioWaveform {
        return AudioWaveform(decibelSamples: [])
    }
}

#endif
