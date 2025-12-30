//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ObjectiveC

public protocol UserErrorDescriptionProvider {
    var localizedDescription: String { get }
}

// MARK: -

extension Error {
    public var hasUserErrorDescription: Bool {
        if self is UserErrorDescriptionProvider {
            return true
        }
        if (self as NSError) is UserErrorDescriptionProvider {
            return true
        }
        if
            let error = self as? LocalizedError,
            nil != error.errorDescription
        {
            return true
        }
        if
            let error = (self as NSError) as? LocalizedError,
            nil != error.errorDescription
        {
            return true
        }
        return false
    }

    public var userErrorDescription: String {
        // Error and NSError have a special relationship.
        // They can be "cast" back and forth, but are separate objects.
        //
        // If Error is cast to NSError, a new NSError will wrap the Error.
        // This is called "NSError bridging".
        //
        // NSError implements Error protocol, but casting NSError to Error
        // might unwrap a bridged wrapper.
        //
        // If you roundtrip-cast Error to NSError and back (or vice versa),
        // you should not count on ending up with the same as instance as
        // you began with, even though you sometimes will.
        //
        // When trying to cast an error to IsRetryableProvider,
        // we need to try casting both the Error and NSError form.
        if let error = self as? UserErrorDescriptionProvider {
            return error.localizedDescription
        }
        if let error = (self as NSError) as? UserErrorDescriptionProvider {
            return error.localizedDescription
        }
        if
            let error = self as? LocalizedError,
            let errorDescription = error.errorDescription
        {
            return errorDescription
        }
        if
            let error = (self as NSError) as? LocalizedError,
            let errorDescription = error.errorDescription
        {
            return errorDescription
        }
        if CurrentAppContext().isRunningTests {
            Logger.warn("Presenting error to user without a specific localizedDescription: \(self)")
        } else {
            owsFailDebug("Presenting error to user without a specific localizedDescription: \(self)")
        }
        return OWSError.genericErrorDescription()
    }
}
