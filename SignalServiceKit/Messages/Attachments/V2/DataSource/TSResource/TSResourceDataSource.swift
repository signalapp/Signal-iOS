//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A DataSource for an attachment to be created locally, with
/// additional required metadata.
public struct TSResourceDataSource {
    let mimeType: String
    let caption: MessageBody?
    private(set) var renderingFlag: AttachmentReference.RenderingFlag
    let sourceFilename: String?

    let dataSource: Source

    public enum Source {
        // V2 Cases
        case pendingAttachment(PendingAttachment)
        case existingV2Attachment(AttachmentDataSource.ExistingAttachmentSource)
    }

    fileprivate init(
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

    public static func forwarding(
        existingAttachment: AttachmentStream,
        with reference: TSResourceReference
    ) -> TSResourceDataSource {
        let reference = reference.concreteType
        let v2 = AttachmentDataSource.forwarding(existingAttachment: existingAttachment, with: reference)

        let caption: MessageBody?
        let renderingFlag: AttachmentReference.RenderingFlag
        switch reference.owner {
        case .message(.bodyAttachment(let metadata)):
            caption = metadata.caption.map { .init(text: $0, ranges: .empty) }
            renderingFlag = metadata.renderingFlag
        case .message(.quotedReply(let metadata)):
            caption = nil
            renderingFlag = metadata.renderingFlag
        case .storyMessage(.media(let metadata)):
            caption = metadata.caption?.asMessageBody()
            renderingFlag = metadata.shouldLoop ? .shouldLoop : .default
        default:
            caption = nil
            renderingFlag = .default
        }

        return .init(
            mimeType: v2.mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            sourceFilename: v2.sourceFilename,
            dataSource: .existingV2Attachment(.init(
                id: existingAttachment.attachment.id,
                mimeType: existingAttachment.mimeType,
                renderingFlag: reference.renderingFlag,
                sourceFilename: reference.sourceFilename,
                sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                sourceMediaSizePixels: reference.sourceMediaSizePixels
            ))
        )
    }

    public static func from(
        pendingAttachment: PendingAttachment
    ) -> TSResourceDataSource {
        return .init(
            mimeType: pendingAttachment.mimeType,
            caption: nil,
            renderingFlag: .default,
            sourceFilename: pendingAttachment.sourceFilename,
            dataSource: .pendingAttachment(pendingAttachment)
        )
    }

    mutating func removeBorderlessRenderingFlagIfPresent() {
        switch renderingFlag {
        case .default, .voiceMessage, .shouldLoop:
            break
        case .borderless:
            renderingFlag = .default
        }
    }
}

extension TSResourceDataSource {

    enum ConcreteType {
        case v2(AttachmentDataSource, AttachmentReference.RenderingFlag)
    }

    var concreteType: ConcreteType {
        switch dataSource {
        case .existingV2Attachment(let metadata):
            return .v2(
                .existingAttachment(metadata),
                renderingFlag
            )
        case .pendingAttachment(let pendingAttachment):
            return .v2(.from(pendingAttachment: pendingAttachment), renderingFlag)
        }
    }
}

extension AttachmentDataSource {

    public var tsDataSource: TSResourceDataSource {
        return .init(
            mimeType: mimeType,
            // Caption and rendering flag live elsewhere
            // for v2 attachments, and aren't on the source.
            caption: nil,
            renderingFlag: .default,
            sourceFilename: sourceFilename,
            dataSource: {
                switch self {
                case let .existingAttachment(existingAttachment):
                    return .existingV2Attachment(existingAttachment)
                case let .pendingAttachment(pendingAttachment):
                    return .pendingAttachment(pendingAttachment)
                }
            }()
        )
    }
}
