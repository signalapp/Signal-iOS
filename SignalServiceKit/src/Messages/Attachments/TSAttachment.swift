//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSAttachment {
    var isFailedDownload: Bool {
        guard let attachmentPointer = self as? TSAttachmentPointer else {
            return false
        }
        return attachmentPointer.state == .failed
    }

    var isPendingMessageRequest: Bool {
        guard let attachmentPointer = self as? TSAttachmentPointer else {
            return false
        }
        return attachmentPointer.state == .pendingMessageRequest
    }

    var isPendingManualDownload: Bool {
        guard let attachmentPointer = self as? TSAttachmentPointer else {
            return false
        }
        return attachmentPointer.state == .pendingManualDownload
    }
}
