//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol LinkPreviewBuilder {

    func buildDataSource(
        _ draft: OWSLinkPreviewDraft
    ) async throws -> LinkPreviewDataSource

    func createLinkPreview(
        from dataSource: LinkPreviewDataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview>

    func createLinkPreview(
        from proto: SSKProtoAttachmentPointer,
        metadata: OWSLinkPreview.Metadata,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview>
}
