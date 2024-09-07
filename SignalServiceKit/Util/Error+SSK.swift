//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Error {
    /// A description comprised of "domain/code" pairs for this error and its underlying errors.
    var shortDescription: String { (self as NSError).shortDescription }
}

@objc
public extension NSError {
    /// A description comprised of "domain/code" pairs for this error and its underlying errors.
    var shortDescription: String {
        var result = [String]()
        var nextError: NSError? = self
        while let currentError = nextError {
            result.append("\(currentError.domain)/\(currentError.code)")
            nextError = currentError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return result.joined(separator: ", ")
    }
}
