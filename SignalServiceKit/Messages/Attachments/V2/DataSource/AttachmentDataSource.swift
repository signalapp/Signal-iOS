//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A DataSource for an attachment to be created locally, with
/// additional required metadata.
public struct AttachmentDataSource {
    let mimeType: String
    let caption: MessageBody?
    let renderingFlag: AttachmentReference.RenderingFlag
    let sourceFilename: String?

    let dataSource: Source

    public enum Source {
        // If shouldCopy=true, the data source will be copied instead of moved.
        case dataSource(DataSource, shouldCopy: Bool)
        case data(Data)
        case existingAttachment(Attachment.IDType)
    }

    internal init(
        mimeType: String,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?,
        dataSource: Source
    ) {
        self.mimeType = mimeType
        self.caption = caption
        self.renderingFlag = renderingFlag
        self.sourceFilename = sourceFilename
        self.dataSource = dataSource
    }

    public static func from(
        dataSource: DataSource,
        mimeType: String,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        shouldCopyDataSource: Bool = false
    ) -> AttachmentDataSource {
        return .init(
            mimeType: mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            sourceFilename: dataSource.sourceFilename,
            dataSource: .dataSource(dataSource, shouldCopy: shouldCopyDataSource)
        )
    }

    public static func from(
        data: Data,
        mimeType: String,
        caption: MessageBody?,
        renderingFlag: AttachmentReference.RenderingFlag,
        sourceFilename: String?
    ) -> AttachmentDataSource {
        return .init(
            mimeType: mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename,
            dataSource: .data(data)
        )
    }

    public static func forwarding(
        existingAttachment: AttachmentStream,
        with reference: AttachmentReference
    ) -> AttachmentDataSource {

        let caption: MessageBody?
        let renderingFlag: AttachmentReference.RenderingFlag
        switch reference.owner {
        case .message(let messageSource):
            switch messageSource {
            case .bodyAttachment(let metadata):
                caption = metadata.caption
                renderingFlag = metadata.renderingFlag
            case .quotedReply(let metadata):
                caption = nil
                renderingFlag = metadata.renderingFlag
            case .oversizeText, .linkPreview, .sticker, .contactAvatar:
                caption = nil
                renderingFlag = .default
            }
        case .storyMessage(let storyMessageSource):
            switch storyMessageSource {
            case .media(let metadata):
                caption = metadata.caption?.asMessageBody()
                renderingFlag = metadata.shouldLoop ? .shouldLoop : .default
            case .textStoryLinkPreview:
                caption = nil
                renderingFlag = .default
            }
        case .thread:
            caption = nil
            renderingFlag = .default
        }

        return .init(
            mimeType: existingAttachment.mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            sourceFilename: reference.sourceFilename,
            dataSource: .existingAttachment(existingAttachment.attachment.id)
        )
    }
}
