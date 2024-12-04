//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct LinkPreviewTSResourceDataSource {
    public let metadata: OWSLinkPreview.Metadata
    public let imageV2DataSource: AttachmentDataSource?

    public func imageDataSource(ownerType: TSResourceOwnerType) -> TSResourceDataSource? {
        return imageV2DataSource?.tsDataSource
    }
}

public class LinkPreviewTSResourceBuilder: LinkPreviewBuilder {

    public typealias DataSource = LinkPreviewTSResourceDataSource

    private let attachmentValidator: AttachmentContentValidator
    private let tsResourceManager: TSResourceManager

    public init(
        attachmentValidator: AttachmentContentValidator,
        tsResourceManager: TSResourceManager
    ) {
        self.attachmentValidator = attachmentValidator
        self.tsResourceManager = tsResourceManager
    }

    public func buildDataSource(
        _ draft: OWSLinkPreviewDraft,
        ownerType: TSResourceOwnerType
    ) throws -> LinkPreviewTSResourceDataSource {
        let metadata = OWSLinkPreview.Metadata(
            urlString: draft.urlString,
            title: draft.title,
            previewDescription: draft.previewDescription,
            date: draft.date
        )
        guard let imageData = draft.imageData, let imageMimeType = draft.imageMimeType else {
            return .init(
                metadata: metadata,
                imageV2DataSource: nil
            )
        }

        let v2DataSource: AttachmentDataSource? = try attachmentValidator.validateContents(
            data: imageData,
            mimeType: imageMimeType,
            renderingFlag: .default,
            sourceFilename: nil
        )

        return .init(
            metadata: metadata,
            imageV2DataSource: v2DataSource
        )
    }

    public func createLinkPreview(
        from dataSource: LinkPreviewTSResourceDataSource,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        guard let imageDataSource = dataSource.imageDataSource(ownerType: ownerType) else {
            return .withoutFinalizer(.withoutImage(metadata: dataSource.metadata, ownerType: ownerType))
        }
        return try tsResourceManager.createAttachmentStreamBuilder(
            from: imageDataSource,
            tx: tx
        ).wrap {
            switch $0 {
            case .legacy(let attachmentId):
                return .withLegacyImageAttachment(metadata: dataSource.metadata, attachmentId: attachmentId)
            case .v2:
                return .withForeignReferenceImageAttachment(metadata: dataSource.metadata, ownerType: ownerType)
            }
        }
    }

    public func createLinkPreview(
        from proto: SSKProtoAttachmentPointer,
        metadata: OWSLinkPreview.Metadata,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try tsResourceManager.createAttachmentPointerBuilder(
            from: proto,
            ownerType: ownerType,
            tx: tx
        ).wrap {
            switch $0 {
            case .legacy(let attachmentId):
                return .withLegacyImageAttachment(metadata: metadata, attachmentId: attachmentId)
            case .v2:
                return .withForeignReferenceImageAttachment(metadata: metadata, ownerType: ownerType)
            }
        }
    }
}

extension LinkPreviewDataSource {

    public var tsResource: LinkPreviewTSResourceDataSource {
        return .init(metadata: metadata, imageV2DataSource: imageDataSource)
    }
}

extension LinkPreviewTSResourceDataSource {

    public var v2DataSource: LinkPreviewDataSource {
        return .init(metadata: metadata, imageDataSource: imageV2DataSource)
    }
}
