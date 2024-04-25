//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum ConcreteTSResource {
    case legacy(TSAttachment)
    case v2(Attachment)
}

public enum ConcreteTSResourceStream {
    case legacy(TSAttachmentStream)
    case v2(AttachmentStream)
}

public enum ConcreteTSResourcePointer {
    case legacy(TSAttachmentPointer)
    case v2(AttachmentTransitPointer)
}
