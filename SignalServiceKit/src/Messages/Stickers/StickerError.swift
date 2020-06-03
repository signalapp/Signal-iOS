//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum StickerError: Int, Error {
    case invalidInput
    case noSticker
    case assertionFailure
    case corruptData
}

extension StickerError: OperationError {
    public var isRetryable: Bool {
        switch self {
        case .invalidInput:
            return false
        case .noSticker:
            return false
        case .assertionFailure:
            return false
        case .corruptData:
            return false
        }
    }
}
