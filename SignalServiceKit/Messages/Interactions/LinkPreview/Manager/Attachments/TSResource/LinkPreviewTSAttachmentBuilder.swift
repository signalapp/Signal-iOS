//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct LinkPreviewTSAttachmentDataSource {
    public let metadata: OWSLinkPreview.Metadata
    public let imageDataSource: TSAttachmentDataSource?
}

public class LinkPreviewTSAttachmentBuilder: LinkPreviewBuilder {

    public typealias DataSource = LinkPreviewTSAttachmentDataSource

    private let tsAttachmentManager: TSAttachmentManager

    public init(
        tsAttachmentManager: TSAttachmentManager
    ) {
        self.tsAttachmentManager = tsAttachmentManager
    }

    public func buildDataSource(
        _ draft: OWSLinkPreviewDraft,
        ownerType: TSResourceOwnerType
    ) throws -> LinkPreviewTSAttachmentDataSource {
        let metadata = OWSLinkPreview.Metadata(
            urlString: draft.urlString,
            title: draft.title,
            previewDescription: draft.previewDescription,
            date: draft.date
        )
        guard let imageData = draft.imageData, let imageMimeType = draft.imageMimeType else {
            return .init(metadata: metadata, imageDataSource: nil)
        }
        return .init(metadata: metadata, imageDataSource: .init(
            mimeType: imageMimeType,
            caption: nil,
            renderingFlag: .default,
            sourceFilename: nil,
            dataSource: .data(imageData)
        ))
    }

    public func createLinkPreview(
        from dataSource: LinkPreviewTSAttachmentDataSource,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard let imageDataSource = dataSource.imageDataSource else {
            return .withoutFinalizer(.withoutImage(metadata: dataSource.metadata, ownerType: ownerType))
        }
        let attachmentId = try tsAttachmentManager.createAttachmentStream(
            from: imageDataSource,
            tx: SDSDB.shimOnlyBridge(tx)
        )
        return .withoutFinalizer(.withLegacyImageAttachment(metadata: dataSource.metadata, attachmentId: attachmentId))
    }

    public func createLinkPreview(
        from proto: SSKProtoAttachmentPointer,
        metadata: OWSLinkPreview.Metadata,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        let attachmentId = try tsAttachmentManager.createAttachmentPointer(
            from: proto,
            tx: SDSDB.shimOnlyBridge(tx)
        ).uniqueId
        return .withoutFinalizer(.withLegacyImageAttachment(metadata: metadata, attachmentId: attachmentId))
    }
}
