// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum LinkPreviewError: Int, Error {
    case invalidInput
    case noPreview
    case assertionFailure
    case couldNotDownload
    case featureDisabled
    case invalidContent
    case invalidMediaContent
    case attachmentFailedToSave
}
