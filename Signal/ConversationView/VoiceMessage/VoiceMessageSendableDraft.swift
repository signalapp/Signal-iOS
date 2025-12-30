//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import Foundation
import SignalServiceKit
import SignalUI
import UniformTypeIdentifiers

protocol VoiceMessageSendableDraft {
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
            VoiceMessageConstants.fileExtension,
        )
    }

    func prepareAttachment() throws -> PreviewableAttachment {
        let attachmentUrl = try prepareForSending()

        let dataSource = DataSourcePath(fileUrl: attachmentUrl, ownership: .owned)
        dataSource.sourceFilename = userVisibleFilename(currentDate: Date())

        return try PreviewableAttachment.voiceMessageAttachment(dataSource: dataSource, dataUTI: UTType.mpeg4Audio.identifier)
    }
}
