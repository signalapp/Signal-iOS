//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct QuotedAttachmentInfo {
    public let info: OWSAttachmentInfo
    public let renderingFlag: AttachmentReference.RenderingFlag

    public init(info: OWSAttachmentInfo, renderingFlag: AttachmentReference.RenderingFlag) {
        self.info = info
        self.renderingFlag = renderingFlag
    }
}
