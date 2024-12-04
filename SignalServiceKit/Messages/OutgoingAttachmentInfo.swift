//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public final class OutgoingAttachmentInfo {
    let dataSource: DataSource
    let contentType: String
    let sourceFilename: String?
    let caption: String?
    let albumMessageId: String?
    let renderingFlag: AttachmentReference.RenderingFlag

    public init(
        dataSource: DataSource,
        contentType: String,
        sourceFilename: String? = nil,
        caption: String? = nil,
        albumMessageId: String? = nil,
        isBorderless: Bool = false,
        isVoiceMessage: Bool = false,
        isLoopingVideo: Bool = false
    ) {
        self.dataSource = dataSource
        self.contentType = contentType
        self.sourceFilename = sourceFilename
        self.caption = caption
        self.albumMessageId = albumMessageId
        self.renderingFlag = {
            if isVoiceMessage {
                return .voiceMessage
            } else if isBorderless {
                return .borderless
            } else if isLoopingVideo || MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(contentType) {
                return .shouldLoop
            } else {
                return .default
            }
        }()
    }

    public func asAttachmentDataSource() throws -> AttachmentDataSource {
        return try DependenciesBridge.shared.attachmentContentValidator.validateContents(
            dataSource: dataSource,
            shouldConsume: true,
            mimeType: contentType,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename
        )
    }
}
