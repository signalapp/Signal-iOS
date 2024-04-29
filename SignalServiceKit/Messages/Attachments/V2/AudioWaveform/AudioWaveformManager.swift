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
        forAttachment attachment: TSResourceStream,
        highPriority: Bool
    ) -> Task<AudioWaveform, Error>

    func audioWaveform(
        forAudioPath audioPath: String,
        waveformPath: String
    ) -> Task<AudioWaveform, Error>
}
