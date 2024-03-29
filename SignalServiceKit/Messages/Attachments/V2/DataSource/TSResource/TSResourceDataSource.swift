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
    let renderingFlag: AttachmentReference.RenderingFlag
    let sourceFilename: String?

    let dataSource: Source

    public enum Source {
        // If shouldCopy=true, the data source will be copied instead of moved.
        case dataSource(DataSource, shouldCopy: Bool)
        case data(Data)
        case existingAttachment(TSResourceId)
    }

    private init(
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
    ) -> TSResourceDataSource {
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
    ) -> TSResourceDataSource {
        return .init(
            mimeType: mimeType,
            caption: caption,
            renderingFlag: renderingFlag,
            sourceFilename: sourceFilename,
            dataSource: .data(data)
        )
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
            return .init(
                mimeType: v2.mimeType,
                caption: v2.caption,
                renderingFlag: v2.renderingFlag,
                sourceFilename: v2.sourceFilename,
                dataSource: .existingAttachment(existingAttachment.resourceId)
            )
        default:
            fatalError("Invalid type combination!")
        }
    }
}

extension TSResourceDataSource {

    enum ConcreteType {
        case legacy(TSAttachmentDataSource)
        case v2(AttachmentDataSource)
    }

    var concreteType: ConcreteType {
        switch dataSource {
        case .dataSource(let dataSource, shouldCopy: let shouldCopy):
            if FeatureFlags.newAttachmentsUseV2 {
                return .v2(.from(
                    dataSource: dataSource,
                    mimeType: mimeType,
                    caption: caption,
                    renderingFlag: renderingFlag,
                    shouldCopyDataSource: shouldCopy
                ))
            } else {
                return .legacy(.init(
                    mimeType: mimeType,
                    caption: caption,
                    renderingFlag: renderingFlag,
                    sourceFilename: sourceFilename,
                    dataSource: .dataSource(dataSource, shouldCopy: shouldCopy)
                ))
            }
        case .data(let data):
            if FeatureFlags.newAttachmentsUseV2 {
                return .v2(.from(
                    data: data,
                    mimeType: mimeType,
                    caption: caption,
                    renderingFlag: renderingFlag,
                    sourceFilename: sourceFilename
                ))
            } else {
                return .legacy(.init(
                    mimeType: mimeType,
                    caption: caption,
                    renderingFlag: renderingFlag,
                    sourceFilename: sourceFilename,
                    dataSource: .data(data)
                ))
            }
        case .existingAttachment(let existingResourceId):
            switch existingResourceId {
            case .v2(let rowId):
                return .v2(.init(
                    mimeType: mimeType,
                    caption: caption,
                    renderingFlag: renderingFlag,
                    sourceFilename: sourceFilename,
                    dataSource: .existingAttachment(rowId)
                ))
            case .legacy(let uniqueId):
                return .legacy(.init(
                    mimeType: mimeType,
                    caption: caption,
                    renderingFlag: renderingFlag,
                    sourceFilename: sourceFilename,
                    dataSource: .existingAttachment(uniqueId: uniqueId)
                ))
            }
        }
    }
}
