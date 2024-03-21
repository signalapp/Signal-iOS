//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A DataSource for an attachment to be created locally, with
/// additional required metadata.
public struct AttachmentDataSource {
    let mimeType: String
    let caption: String?
    let renderingFlag: AttachmentReference.RenderingFlag

    let dataSource: DataSource

    var sourceFilename: String? { dataSource.sourceFilename }
    var dataLength: UInt { dataSource.dataLength }

    public init(
        mimeType: String,
        caption: String?,
        renderingFlag: AttachmentReference.RenderingFlag,
        dataSource: DataSource
    ) {
        self.mimeType = mimeType
        self.caption = caption
        self.renderingFlag = renderingFlag
        self.dataSource = dataSource
    }
}
