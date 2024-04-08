//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class LinkPreviewTSAttachmentBuilder: LinkPreviewBuilder {

    public typealias DataSource = TSAttachmentDataSource

    private let tsAttachmentManager: TSAttachmentManager

    public init(
        tsAttachmentManager: TSAttachmentManager
    ) {
        self.tsAttachmentManager = tsAttachmentManager
    }

    public static func buildAttachmentDataSource(
        data: Data,
        mimeType: String
    ) -> DataSource {
        return TSAttachmentDataSource(
            mimeType: mimeType,
            caption: nil,
            renderingFlag: .default,
            sourceFilename: nil,
            dataSource: .data(data)
        )
    }

    public func createLinkPreview(
        from dataSource: DataSource,
        metadata: OWSLinkPreview.Metadata,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        let attachmentId = try tsAttachmentManager.createAttachmentStream(
            from: dataSource,
            tx: SDSDB.shimOnlyBridge(tx)
        )
        return .withoutFinalizer(.withLegacyImageAttachment(metadata: metadata, attachmentId: attachmentId))
    }

    public func createLinkPreview(
        from proto: SSKProtoAttachmentPointer,
        metadata: OWSLinkPreview.Metadata,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        let attachmentId = try tsAttachmentManager.createAttachmentPointer(
            from: proto,
            tx: SDSDB.shimOnlyBridge(tx)
        ).uniqueId
        return .withoutFinalizer(.withLegacyImageAttachment(metadata: metadata, attachmentId: attachmentId))
    }
}
