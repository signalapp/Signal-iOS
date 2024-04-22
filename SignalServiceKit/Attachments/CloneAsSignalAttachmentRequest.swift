//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The purpose of this request is to make it possible to cloneAsSignalAttachment without an instance of the original TSAttachmentStream.
/// See the note in VideoDurationHelper for why.
public struct CloneAsSignalAttachmentRequest {
    public var uniqueId: String
    public var sourceUrl: URL
    public var dataUTI: String
    public var sourceFilename: String?
    public var isVoiceMessage: Bool
    public var caption: String?
    public var isBorderless: Bool
    public var isLoopingVideo: Bool

    public init(
        uniqueId: String,
        sourceUrl: URL,
        dataUTI: String,
        sourceFilename: String?,
        isVoiceMessage: Bool,
        caption: String?,
        isBorderless: Bool,
        isLoopingVideo: Bool
    ) {
        self.uniqueId = uniqueId
        self.sourceUrl = sourceUrl
        self.dataUTI = dataUTI
        self.sourceFilename = sourceFilename
        self.isVoiceMessage = isVoiceMessage
        self.caption = caption
        self.isBorderless = isBorderless
        self.isLoopingVideo = isLoopingVideo
    }
}
