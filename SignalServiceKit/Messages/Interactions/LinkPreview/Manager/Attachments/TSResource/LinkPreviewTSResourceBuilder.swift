//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct LinkPreviewTSResourceDataSource {
    public let metadata: OWSLinkPreview.Metadata
    public let imageV2DataSource: AttachmentDataSource?
    public let imageLegacyDataSource: TSAttachmentDataSource?

    public func imageDataSource(ownerType: TSResourceOwnerType) -> TSResourceDataSource? {
        if let imageV2DataSource {
            return imageV2DataSource.tsDataSource
        } else {
            return imageLegacyDataSource?.tsDataSource
        }
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
                imageV2DataSource: nil,
                imageLegacyDataSource: nil
            )
        }

        // At the time we convert a draft to a data source, we don't
        // yet know if we will need a v2 AttachmentDataSource or a
        // legacy TSAttachmentDataSource, so create both.
        // In particular, for message edits we never want to mix & match
        // legacy and v2 attachments; if the message has a legacy quote on
        // it we want the link preview to be legacy too, even if we have
        // since started using v2 for new attachments.
        let v2DataSource: AttachmentDataSource? = try attachmentValidator.validateContents(
            data: imageData,
            mimeType: imageMimeType,
            renderingFlag: .default,
            sourceFilename: nil
        )

        let legacyDataSource = TSAttachmentDataSource(
            mimeType: imageMimeType,
            caption: nil,
            renderingFlag: .default,
            sourceFilename: nil,
            dataSource: .data(imageData)
        )
        return .init(
            metadata: metadata,
            imageV2DataSource: v2DataSource,
            imageLegacyDataSource: legacyDataSource
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
        return .init(metadata: metadata, imageV2DataSource: imageDataSource, imageLegacyDataSource: nil)
    }
}

extension LinkPreviewTSAttachmentDataSource {

    public var tsResource: LinkPreviewTSResourceDataSource {
        return .init(metadata: metadata, imageV2DataSource: nil, imageLegacyDataSource: imageDataSource)
    }
}

extension LinkPreviewTSResourceDataSource {

    public var v2DataSource: LinkPreviewDataSource {
        return .init(metadata: metadata, imageDataSource: imageV2DataSource)
    }

    public var legacyDataSource: LinkPreviewTSAttachmentDataSource {
        return .init(metadata: metadata, imageDataSource: imageLegacyDataSource)
    }
}
