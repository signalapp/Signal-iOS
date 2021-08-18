//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum StickerError: Int, Error, IsRetryableProvider {
    case invalidInput
    case noSticker
    case assertionFailure
    case corruptData

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { false }
}
