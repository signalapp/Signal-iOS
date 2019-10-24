//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension OWSAttachmentDownloads {
    func downloadAttachmentPointer(_ attachmentPointer: TSAttachmentPointer, message: TSMessage?) -> Promise<TSAttachmentStream> {
        return Promise { resolver in
            self.downloadAttachmentPointer(attachmentPointer,
                                           message: message,
                                           success: resolver.fulfill,
                                           failure: resolver.reject)
        }.map { attachments in
            assert(attachments.count == 1)
            guard let attachment = attachments.first else {
                throw OWSAssertionError("missing attachment after download")
            }
            return attachment
        }
    }
}
