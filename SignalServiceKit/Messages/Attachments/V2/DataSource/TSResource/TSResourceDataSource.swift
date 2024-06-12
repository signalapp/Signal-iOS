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
        // If shouldCopy=true, the data source will be copied instead of moved.
        case dataSource(DataSource, shouldCopy: Bool)
        case data(Data)
        case existingAttachment(TSResourceId)
        case pendingAttachment(PendingAttachment)
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
        existingAttachment: TSResourceStream,
        with reference: TSResourceReference
    ) -> TSResourceDataSource {
        switch (existingAttachment.concreteStreamType, reference.concreteType) {
        case (.legacy(let attachment), .legacy(let reference)):
            let caption: MessageBody? =
                reference.storyMediaCaption?.asMessageBody()
                ?? attachment.caption.map { MessageBody(text: $0, ranges: .empty) }
            return .init(
                mimeType: attachment.mimeType,
                caption: caption,
                renderingFlag: reference.renderingFlag,
                sourceFilename: reference.sourceFilename,
                dataSource: .existingAttachment(existingAttachment.resourceId)
            )
        case (.v2(let attachment), .v2(let reference)):
            let v2 = AttachmentDataSource.forwarding(existingAttachment: attachment, with: reference)

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
                dataSource: .existingAttachment(existingAttachment.resourceId)
            )
        default:
            fatalError("Invalid type combination!")
        }
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
        case legacy(TSAttachmentDataSource)
        case v2(AttachmentDataSource, AttachmentReference.RenderingFlag)
    }

    var concreteType: ConcreteType {
        switch dataSource {
        case .dataSource(let dataSource, shouldCopy: let shouldCopy):
            return .legacy(.init(
                mimeType: mimeType,
                caption: caption,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename,
                dataSource: .dataSource(dataSource, shouldCopy: shouldCopy)
            ))
        case .data(let data):
            return .legacy(.init(
                mimeType: mimeType,
                caption: caption,
                renderingFlag: renderingFlag,
                sourceFilename: sourceFilename,
                dataSource: .data(data)
            ))
        case .existingAttachment(let existingResourceId):
            switch existingResourceId {
            case .v2(let rowId):
                return .v2(
                    .init(
                        mimeType: mimeType,
                        contentHash: nil,
                        sourceFilename: sourceFilename,
                        dataSource: .existingAttachment(rowId)
                    ),
                    renderingFlag
                )
            case .legacy(let uniqueId):
                return .legacy(.init(
                    mimeType: mimeType,
                    caption: caption,
                    renderingFlag: renderingFlag,
                    sourceFilename: sourceFilename,
                    dataSource: .existingAttachment(uniqueId: uniqueId)
                ))
            }
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
                switch self.dataSource {
                case let .existingAttachment(attachmentId):
                    return .existingAttachment(.v2(rowId: attachmentId))
                case let .pendingAttachment(pendingAttachment):
                    return .pendingAttachment(pendingAttachment)
                }
            }()
        )
    }
}

extension TSAttachmentDataSource {
    public var tsDataSource: TSResourceDataSource {
        return .init(
            mimeType: mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename,
            dataSource: {
                switch dataSource {
                case .dataSource(let dataSource, let shouldCopy):
                    return .dataSource(dataSource, shouldCopy: shouldCopy)
                case .data(let data):
                    return .data(data)
                case .existingAttachment(let uniqueId):
                    return .existingAttachment(.legacy(uniqueId: uniqueId))
                }
            }()
        )
    }
}
