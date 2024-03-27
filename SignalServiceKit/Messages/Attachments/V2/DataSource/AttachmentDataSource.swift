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

    // If true, the data source will be copied instead of moved.
    let shouldCopyDataSource: Bool
    let dataSource: DataSource

    var sourceFilename: String? { dataSource.sourceFilename }
    var dataLength: UInt { dataSource.dataLength }

    public init(
        mimeType: String,
        caption: String?,
        renderingFlag: AttachmentReference.RenderingFlag,
        dataSource: DataSource,
        shouldCopyDataSource: Bool = false
    ) {
        self.mimeType = mimeType
        self.caption = caption
        self.renderingFlag = renderingFlag
        self.dataSource = dataSource
        self.shouldCopyDataSource = shouldCopyDataSource
    }
}
