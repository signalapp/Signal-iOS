//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import Foundation
import SignalServiceKit
import SignalUI
import UniformTypeIdentifiers
import AVFoundation

enum VoiceMessageRecordingFormat: String {
    case m4a
    case wav

    var fileExtension: String {
        switch self {
        case .m4a:
            return "m4a"
        case .wav:
            return "wav"
        }
    }

    var dataUTI: String {
        switch self {
        case .m4a:
            return UTType.mpeg4Audio.identifier
        case .wav:
            return UTType.wav.identifier
        }
    }

    var recorderSettings: [String: Any] {
        switch self {
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32000,
            ]
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        }
    }
}

protocol VoiceMessageSendableDraft {
    var voiceMessageRecordingFormat: VoiceMessageRecordingFormat { get }
    func prepareForSending() throws -> URL
}

extension VoiceMessageSendableDraft {
    private func userVisibleFilename(currentDate: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss-SSS"
        let dateString = dateFormatter.string(from: Date())
        return String(
            format: "signal-%@.%@",
            dateString,
            voiceMessageRecordingFormat.fileExtension,
        )
    }

    func prepareAttachment(attachmentLimits: OutgoingAttachmentLimits) throws -> PreviewableAttachment {
        let attachmentUrl = try prepareForSending()

        let dataSource = DataSourcePath(fileUrl: attachmentUrl, ownership: .owned)
        dataSource.sourceFilename = userVisibleFilename(currentDate: Date())

        return try PreviewableAttachment.voiceMessageAttachment(
            dataSource: dataSource,
            dataUTI: voiceMessageRecordingFormat.dataUTI,
            attachmentLimits: attachmentLimits,
        )
    }
}
