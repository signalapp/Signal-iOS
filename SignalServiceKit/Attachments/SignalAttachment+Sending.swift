//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension SendableAttachment {

    public struct ForSending {
        public let dataSource: AttachmentDataSource
        public let renderingFlag: AttachmentReference.RenderingFlag

        public init(dataSource: AttachmentDataSource, renderingFlag: AttachmentReference.RenderingFlag) {
            self.dataSource = dataSource
            self.renderingFlag = renderingFlag
        }
    }

    public func forSending(attachmentContentValidator: any AttachmentContentValidator) async throws -> ForSending {
        let dataSource = try await attachmentContentValidator.validateContents(
            sendableAttachment: self,
            shouldUseDefaultFilename: true,
        )
        return ForSending(
            dataSource: dataSource,
            renderingFlag: self.renderingFlag,
        )
    }
}
