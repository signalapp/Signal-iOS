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

extension AttachmentThumbnailQuality {

    public static func pointSize(pixelSize: CGSize) -> CGSize {
        let factor = 1 / UIScreen.main.scale
        return CGSize(
            width: pixelSize.width * factor,
            height: pixelSize.height * factor
        )
    }

    private static let thumbnailDimensionPointsSmall: CGFloat = 200
    private static let thumbnailDimensionPointsMedium: CGFloat = 450
    private static let thumbnailDimensionPointsMediumLarge: CGFloat = 600

    public static let thumbnailDimensionPointsForQuotedReply = thumbnailDimensionPointsSmall

    // This size is large enough to render full screen.
    private static func thumbnailDimensionPointsLarge() -> CGFloat {
        let screenSizePoints = UIScreen.main.bounds.size
        return max(screenSizePoints.width, screenSizePoints.height)
    }

    public func thumbnailDimensionPoints() -> CGFloat {
        switch self {
        case .small:
            return Self.thumbnailDimensionPointsSmall
        case .medium:
            return Self.thumbnailDimensionPointsMedium
        case .mediumLarge:
            return Self.thumbnailDimensionPointsMediumLarge
        case .large:
            return Self.thumbnailDimensionPointsLarge()
        }
    }
}
