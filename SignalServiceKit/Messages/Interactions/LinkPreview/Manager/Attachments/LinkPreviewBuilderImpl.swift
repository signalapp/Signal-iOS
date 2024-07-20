//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct LinkPreviewDataSource {
    public let metadata: OWSLinkPreview.Metadata
    public let imageDataSource: AttachmentDataSource?
}

public class LinkPreviewBuilderImpl: LinkPreviewBuilder {

    public typealias DataSource = LinkPreviewDataSource

    private let attachmentManager: AttachmentManager
    private let attachmentValidator: AttachmentContentValidator

    public init(
        attachmentManager: AttachmentManager,
        attachmentValidator: AttachmentContentValidator
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentValidator = attachmentValidator
    }

    public func buildDataSource(
        _ draft: OWSLinkPreviewDraft,
        ownerType: TSResourceOwnerType
    ) throws -> LinkPreviewDataSource {
        let metadata = OWSLinkPreview.Metadata(
            urlString: draft.urlString,
            title: draft.title,
            previewDescription: draft.previewDescription,
            date: draft.date
        )
        guard let imageData = draft.imageData, let imageMimeType = draft.imageMimeType else {
            return .init(metadata: metadata, imageDataSource: nil)
        }
        let imageDataSource: AttachmentDataSource = try attachmentValidator.validateContents(
            data: imageData,
            mimeType: imageMimeType,
            renderingFlag: .default,
            sourceFilename: nil
        )
        return .init(metadata: metadata, imageDataSource: imageDataSource)
    }

    public func createLinkPreview(
        from dataSource: LinkPreviewDataSource,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard let imageDataSource = dataSource.imageDataSource else {
            return .withoutFinalizer(.withoutImage(metadata: dataSource.metadata, ownerType: ownerType))
        }
        return OwnedAttachmentBuilder<OWSLinkPreview>(
            info: .withForeignReferenceImageAttachment(metadata: dataSource.metadata, ownerType: ownerType),
            finalize: { [attachmentManager] owner, innerTx in
                return try attachmentManager.createAttachmentStream(
                    consuming: .init(dataSource: imageDataSource, owner: owner),
                    tx: innerTx
                )
            }
        )
    }

    public func createLinkPreview(
        from proto: SSKProtoAttachmentPointer,
        metadata: OWSLinkPreview.Metadata,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return OwnedAttachmentBuilder<OWSLinkPreview>(
            info: .withForeignReferenceImageAttachment(metadata: metadata, ownerType: ownerType),
            finalize: { [attachmentManager] owner, innerTx in
                return try attachmentManager.createAttachmentPointer(
                    from: .init(proto: proto, owner: owner),
                    tx: innerTx
                )
            }
        )
    }
}
