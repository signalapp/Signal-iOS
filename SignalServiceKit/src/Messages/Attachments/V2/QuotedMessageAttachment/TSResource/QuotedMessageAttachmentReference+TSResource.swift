//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension QuotedMessageAttachmentReference {

    var tsReference: TSQuotedMessageResourceReference {
        switch self {
        case .thumbnail(let attachmentRef):
            return .thumbnail(attachmentRef)
        case .stub(let stub):
            return .stub(stub)
        }
    }
}
