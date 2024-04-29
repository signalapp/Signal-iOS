//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class AudioWaveformManagerMock: AudioWaveformManager {

    public init() {}

    public func audioWaveform(forAttachment attachment: TSResourceStream, highPriority: Bool) -> Task<AudioWaveform, Error> {
        return Task {
            return AudioWaveform(decibelSamples: [])
        }
    }

    public func audioWaveform(forAudioPath audioPath: String, waveformPath: String) -> Task<AudioWaveform, Error> {
        return Task {
            return AudioWaveform(decibelSamples: [])
        }
    }
}

#endif
