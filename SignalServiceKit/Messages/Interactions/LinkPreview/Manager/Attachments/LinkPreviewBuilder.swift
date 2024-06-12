//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol LinkPreviewBuilder {

    associatedtype DataSource

    func buildDataSource(
        _ draft: OWSLinkPreviewDraft
    ) throws -> DataSource

    func createLinkPreview(
        from dataSource: DataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview>

    func createLinkPreview(
        from proto: SSKProtoAttachmentPointer,
        metadata: OWSLinkPreview.Metadata,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview>
}
