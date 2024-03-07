//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum ConcreteTSResourceReference {
    case legacy(TSAttachmentReference)
    case v2(AttachmentReference)
}
