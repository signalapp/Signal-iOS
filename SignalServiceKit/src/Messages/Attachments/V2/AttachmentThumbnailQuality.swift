//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AttachmentThumbnailQuality {
    case small
    case medium
    case mediumLarge
    case large
}

extension AttachmentThumbnailQuality: CustomStringConvertible {
    public var description: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .mediumLarge:
            return "MediumLarge"
        case .large:
            return "Large"
        }
    }
}
