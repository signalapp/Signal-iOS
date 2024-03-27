//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
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

// MARK: -

extension SDSError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidResult:
            return "SDSError.invalidResult"
        case .missingRequiredField:
            return "SDSError.missingRequiredField"
        case .unexpectedType:
            return "SDSError.unexpectedType"
        case .invalidValue:
            return "SDSError.invalidValue"
        case .invalidTransaction:
            return "SDSError.invalidTransaction"
        @unknown default:
            owsFailDebug("unexpected value: \(self.rawValue)")
            return "SDSError.Unknown"
        }
    }
}
