//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ObjectiveC

extension NSError {

    @objc
    public var hasIsRetryable: Bool { hasIsRetryableImpl }

    @objc
    public var isRetryable: Bool { isRetryableImpl }
}

// MARK: -

extension Error {
    public var hasIsRetryable: Bool { (self as NSError).hasIsRetryable }

    public var isRetryable: Bool { (self as NSError).isRetryableImpl }
}

// MARK: -

extension NSError {

    fileprivate var hasIsRetryableImpl: Bool {
        if self is IsRetryableProvider {
            return true
        }
        if self.isNetworkFailureOrTimeout {
            return true
        }
        return false
    }

    fileprivate var isRetryableImpl: Bool {
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
        if let error = self as? IsRetryableProvider {
            return error.isRetryableProvider
        }
        if let error = (self as Error) as? IsRetryableProvider {
            return error.isRetryableProvider
        }

        if self.isNetworkFailureOrTimeout {
            // We can safely default to retrying network failures.
            Logger.verbose("Network error without retry behavior specified: \(self)")
            return true
        }
        // Do not retry generic 4xx errors.
        //
        // If there are any 4xx errors that we want to retry, we should catch them
        // and throw a custom Error that implements IsRetryableProvider.
        if let statusCode = self.httpStatusCode,
           statusCode >= 400,
           statusCode <= 499 {
            Logger.info("Not retrying error: \(statusCode), \(String(describing: (self as Error).httpRequestUrl))")
            return false
        }

        // This value should always be set for all errors by this
        // var is consulted.  If not, default to retrying in production.
        if CurrentAppContext().isRunningTests {
            Logger.warn("Error without retry behavior specified: \(self)")
        } else {
            owsFailDebug("Error without retry behavior specified: \(self)")
        }
        return true
    }
}

// MARK: -

public protocol IsRetryableProvider {
    var isRetryableProvider: Bool { get }
}

// MARK: -

extension OWSAssertionError: IsRetryableProvider {
    public var isRetryableProvider: Bool { false }
}

extension OWSGenericError: IsRetryableProvider {
    public var isRetryableProvider: Bool { false }
}

// MARK: -

// NOTE: We typically prefer to use a more specific error.
@objc
public class OWSRetryableError: NSObject, CustomNSError, IsRetryableProvider {
    @objc
    public static var asNSError: NSError {
        OWSRetryableError() as Error as NSError
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { true }
}

// MARK: -

// NOTE: We typically prefer to use a more specific error.
@objc
public class OWSUnretryableError: NSObject, CustomNSError, IsRetryableProvider {
    @objc
    public static var asNSError: NSError {
        OWSUnretryableError() as Error as NSError
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { false }
}

// MARK: -

public enum SSKUnretryableError: Error, IsRetryableProvider {
    case paymentsReconciliationFailure
    case paymentsProcessingFailure
    case partialLocalProfileFetch
    case stickerDecryptionFailure
    case stickerMissingFile
    case stickerOversizeFile
    case downloadCouldNotMoveFile
    case downloadCouldNotDeleteFile
    case invalidThread
    case messageProcessingFailed
    case couldNotLoadFileData
    case restoreGroupFailed

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { false }
}
