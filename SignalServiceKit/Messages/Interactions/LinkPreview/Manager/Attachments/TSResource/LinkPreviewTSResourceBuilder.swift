//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class LinkPreviewTSResourceBuilder: LinkPreviewBuilder {

    public typealias DataSource = TSResourceDataSource

    private let tsResourceManager: TSResourceManager

    public init(
        tsResourceManager: TSResourceManager
    ) {
        self.tsResourceManager = tsResourceManager
    }

    public static func buildAttachmentDataSource(
        data: Data,
        mimeType: String
    ) -> DataSource {
        return TSResourceDataSource.from(
            data: data,
            mimeType: mimeType,
            caption: nil,
            renderingFlag: .default,
            sourceFilename: nil
        )
    }

    public func createLinkPreview(
        from dataSource: DataSource,
        metadata: OWSLinkPreview.Metadata,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try tsResourceManager.createAttachmentStreamBuilder(
            from: dataSource,
            tx: tx
        ).wrap {
            switch $0 {
            case .legacy(let attachmentId):
                return .withLegacyImageAttachment(metadata: metadata, attachmentId: attachmentId)
            case .v2:
                return .withForeignReferenceImageAttachment(metadata: metadata)
            }
        }
    }

    public func createLinkPreview(
        from proto: SSKProtoAttachmentPointer,
        metadata: OWSLinkPreview.Metadata,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return try tsResourceManager.createAttachmentPointerBuilder(
            from: proto,
            tx: tx
        ).wrap {
            switch $0 {
            case .legacy(let attachmentId):
                return .withLegacyImageAttachment(metadata: metadata, attachmentId: attachmentId)
            case .v2:
                return .withForeignReferenceImageAttachment(metadata: metadata)
            }
        }
    }
}
