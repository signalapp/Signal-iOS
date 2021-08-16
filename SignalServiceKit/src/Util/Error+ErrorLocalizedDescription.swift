//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import ObjectiveC

public protocol ErrorLocalizedDescriptionProvider {
    var localizedDescription: String { get }
}

// MARK: -

extension Error {
    public var hasErrorLocalizedDescription: Bool { (self as NSError).hasErrorLocalizedDescriptionImpl }
    public var errorLocalizedDescription: String { (self as NSError).errorLocalizedDescriptionImpl }
}

// MARK: -

extension NSError {
    @objc
    public var hasErrorLocalizedDescription: Bool { hasErrorLocalizedDescriptionImpl }

    @objc
    public var errorLocalizedDescription: String { errorLocalizedDescriptionImpl }

    fileprivate var hasErrorLocalizedDescriptionImpl: Bool {
        if self is ErrorLocalizedDescriptionProvider {
            return true
        }
        if (self as Error) is ErrorLocalizedDescriptionProvider {
            return true
        }
        if let error = self as? LocalizedError,
           nil != error.errorDescription {
            return true
        }
        if let error = (self as Error) as? LocalizedError,
           nil != error.errorDescription {
            return true
        }
        return false
    }

    fileprivate var errorLocalizedDescriptionImpl: String {
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
        if let error = self as? ErrorLocalizedDescriptionProvider {
            return error.localizedDescription
        }
        if let error = (self as Error) as? ErrorLocalizedDescriptionProvider {
            return error.localizedDescription
        }
        if let error = self as? LocalizedError,
           let errorDescription = error.errorDescription {
            return errorDescription
        }
        if let error = (self as Error) as? LocalizedError,
           let errorDescription = error.errorDescription {
            return errorDescription
        }
        if CurrentAppContext().isRunningTests {
            Logger.warn("Presenting error to user without a specific localizedDescription: \(self)")
        } else {
            owsFailDebug("Presenting error to user without a specific localizedDescription: \(self)")
        }
        return NSLocalizedString("ERROR_DESCRIPTION_UNKNOWN_ERROR",
                                 comment: "Worst case generic error message")
    }
}
