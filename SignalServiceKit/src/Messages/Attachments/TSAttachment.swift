//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

// MARK: -

@objc
public extension TSAttachmentStream {

    var imageSizePoints: CGSize {
        let imageSizePixels = self.imageSizePixels
        let factor = 1 / UIScreen.main.scale
        return CGSize(width: imageSizePixels.width * factor,
                      height: imageSizePixels.height * factor)
    }

    static let thumbnailDimensionPointsSmall: CGFloat = 200
    static let thumbnailDimensionPointsMedium: CGFloat = 450
    static let thumbnailDimensionPointsMediumLarge: CGFloat = 600

    // This size is large enough to render full screen.
    static func thumbnailDimensionPointsLarge() -> CGFloat {
        let screenSizePoints = UIScreen.main.bounds.size
        return max(screenSizePoints.width, screenSizePoints.height)
    }

    // This size is large enough to render full screen.
    static func thumbnailDimensionPoints(forThumbnailQuality thumbnailQuality: AttachmentThumbnailQuality) -> CGFloat {
        switch thumbnailQuality {
        case .small:
            return thumbnailDimensionPointsSmall
        case .medium:
            return thumbnailDimensionPointsMedium
        case .mediumLarge:
            return thumbnailDimensionPointsMediumLarge
        case .large:
            return thumbnailDimensionPointsLarge()
        }
    }

    func thumbnailImageSmall(success: @escaping OWSThumbnailSuccess, failure: @escaping OWSThumbnailFailure) {
        thumbnailImage(quality: .small, success: success, failure: failure)
    }

    func thumbnailImageMedium(success: @escaping OWSThumbnailSuccess, failure: @escaping OWSThumbnailFailure) {
        thumbnailImage(quality: .medium, success: success, failure: failure)
    }

    func thumbnailImageMediumLarge(success: @escaping OWSThumbnailSuccess, failure: @escaping OWSThumbnailFailure) {
        thumbnailImage(quality: .mediumLarge, success: success, failure: failure)
    }

    func thumbnailImageLarge(success: @escaping OWSThumbnailSuccess, failure: @escaping OWSThumbnailFailure) {
        thumbnailImage(quality: .large, success: success, failure: failure)
    }

    func thumbnailImageSmallSync() -> UIImage? {
        thumbnailImageSync(quality: .small)
    }

    func thumbnailImageMediumSync() -> UIImage? {
        thumbnailImageSync(quality: .medium)
    }

    func thumbnailImageMediumLargeSync() -> UIImage? {
        thumbnailImageSync(quality: .mediumLarge)
    }

    func thumbnailImageLargeSync() -> UIImage? {
        thumbnailImageSync(quality: .large)
    }
}
