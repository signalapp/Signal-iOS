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
    let isBorderless: Bool
    let isLoopingVideo: Bool

    public init(
        dataSource: DataSource,
        contentType: String,
        sourceFilename: String? = nil,
        caption: String? = nil,
        albumMessageId: String? = nil,
        isBorderless: Bool = false,
        isLoopingVideo: Bool = false
    ) {
        self.dataSource = dataSource
        self.contentType = contentType
        self.sourceFilename = sourceFilename
        self.caption = caption
        self.albumMessageId = albumMessageId
        self.isBorderless = isBorderless
        self.isLoopingVideo = isLoopingVideo
    }

    public func asStreamConsumingDataSource(isVoiceMessage: Bool) throws -> TSAttachmentStream {
        let attachmentType: TSAttachmentType
        if isVoiceMessage {
            attachmentType = .voiceMessage
        } else if isBorderless {
            attachmentType = .borderless
        } else if isLoopingVideo || MIMETypeUtil.isDefinitelyAnimated(contentType) {
            attachmentType = .GIF
        } else {
            attachmentType = .default
        }

        let attachmentStream = TSAttachmentStream(
            contentType: contentType,
            byteCount: UInt32(dataSource.dataLength),
            sourceFilename: sourceFilename,
            caption: caption,
            attachmentType: attachmentType,
            albumMessageId: albumMessageId
        )

        try attachmentStream.writeConsumingDataSource(dataSource)

        return attachmentStream
    }
}
