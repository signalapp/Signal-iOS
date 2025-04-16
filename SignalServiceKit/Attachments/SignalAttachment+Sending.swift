//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension SignalAttachment {
    
    public struct ForSending {
        public let dataSource: AttachmentDataSource
        public let isViewOnce: Bool
        public let renderingFlag: AttachmentReference.RenderingFlag

        public init(dataSource: AttachmentDataSource, isViewOnce: Bool, renderingFlag: AttachmentReference.RenderingFlag) {
            self.dataSource = dataSource
            self.isViewOnce = isViewOnce
            self.renderingFlag = renderingFlag
        }
    }
    
}

extension Array<SignalAttachment> {

//    public func forSending() throws -> [SignalAttachment.ForSending] {
//        let dataSource = try self.buildAttachmentDataSource()
//        return .init(
//            dataSource: dataSource,
//            isViewOnce: self.isViewOnceAttachment,
//            renderingFlag: self.renderingFlag
//        )
//    }
    
    public func forSending() throws -> [SignalAttachment.ForSending] {
        var results = [SignalAttachment.ForSending]()
        for attachment in self {
            let dataSource = try attachment.buildAttachmentDataSource()
            let result = SignalAttachment.ForSending(dataSource: dataSource, isViewOnce: attachment.isViewOnceAttachment, renderingFlag: attachment.renderingFlag)
        }
        return results
    }
}
