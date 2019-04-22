//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum StickerError: Int, Error {
    case invalidInput
    case noSticker
    case assertionFailure
    case redundantOperation
}
