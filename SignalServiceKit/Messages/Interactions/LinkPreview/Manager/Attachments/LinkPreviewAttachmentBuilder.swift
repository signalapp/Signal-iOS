//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class LinkPreviewAttachmentBuilder: LinkPreviewBuilder {

    public typealias DataSource = AttachmentDataSource

    private let attachmentManager: AttachmentManager

    public init(
        attachmentManager: AttachmentManager
    ) {
        self.attachmentManager = attachmentManager
    }

    public static func buildAttachmentDataSource(
        data: Data,
        mimeType: String
    ) -> DataSource {
        return AttachmentDataSource.from(
            data: data,
            mimeType: mimeType
        )
    }

    public func createLinkPreview(
        from dataSource: DataSource,
        metadata: OWSLinkPreview.Metadata,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return OwnedAttachmentBuilder<OWSLinkPreview>(
            info: .withForeignReferenceImageAttachment(metadata: metadata),
            finalize: { [attachmentManager] owner, innerTx in
                return try attachmentManager.createAttachmentStream(
                    consuming: .init(dataSource: dataSource, owner: owner),
                    tx: innerTx
                )
            }
        )
    }

    public func createLinkPreview(
        from proto: SSKProtoAttachmentPointer,
        metadata: OWSLinkPreview.Metadata,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return OwnedAttachmentBuilder<OWSLinkPreview>(
            info: .withForeignReferenceImageAttachment(metadata: metadata),
            finalize: { [attachmentManager] owner, innerTx in
                return try attachmentManager.createAttachmentPointer(
                    from: .init(proto: proto, owner: owner),
                    tx: innerTx
                )
            }
        )
    }
}
