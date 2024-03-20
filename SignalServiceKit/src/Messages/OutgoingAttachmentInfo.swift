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
            } else if isLoopingVideo || MIMETypeUtil.isDefinitelyAnimated(contentType) {
                return .shouldLoop
            } else {
                return .default
            }
        }()
    }

    public func asStreamConsumingDataSource() throws -> TSAttachmentStream {
        let attachmentStream = TSAttachmentStream(
            contentType: contentType,
            byteCount: UInt32(dataSource.dataLength),
            sourceFilename: sourceFilename,
            caption: caption,
            attachmentType: renderingFlag.tsAttachmentType,
            albumMessageId: albumMessageId
        )

        try attachmentStream.writeConsumingDataSource(dataSource)

        return attachmentStream
    }
}
