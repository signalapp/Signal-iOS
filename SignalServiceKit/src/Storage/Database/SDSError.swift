//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

// TODO: Perhaps we should replace all of these with assertionError.
@objc
public enum SDSError: Int, Error {
    // TODO: We may want to add a description parameter to these errors.
    case invalidResult
    case missingRequiredField
    case unexpectedType
    case invalidValue
    case invalidTransaction
}
