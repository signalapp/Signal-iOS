//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ObjectiveC
public import SwiftProtobuf

extension Error {
    public var hasIsRetryable: Bool {
        if self is IsRetryableProvider {
            return true
        }
        if self.isNetworkFailureOrTimeout {
            return true
        }
        return false
    }

    public var isRetryable: Bool {
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
        if let error = (self as NSError) as? IsRetryableProvider {
            return error.isRetryableProvider
        }

        if self.isNetworkFailureOrTimeout {
            // We can safely default to retrying network failures.
            return true
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

extension CancellationError: IsRetryableProvider {
    public var isRetryableProvider: Bool { false }
}

extension SwiftProtobuf.BinaryDecodingError: IsRetryableProvider {
    public var isRetryableProvider: Bool { false }
}

extension SwiftProtobuf.BinaryEncodingError: IsRetryableProvider {
    public var isRetryableProvider: Bool { false }
}

// MARK: -

// NOTE: We typically prefer to use a more specific error.
public class OWSRetryableError: CustomNSError, IsRetryableProvider {
    public static var asNSError: NSError {
        OWSRetryableError() as Error as NSError
    }

    public init() {
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { true }
}

// MARK: -

// NOTE: We typically prefer to use a more specific error.
public class OWSUnretryableError: CustomNSError, IsRetryableProvider {
    public static var asNSError: NSError {
        OWSUnretryableError() as Error as NSError
    }

    public init() {}

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { false }
}

// MARK: -

public enum SSKUnretryableError: Error, IsRetryableProvider {
    case stickerDecryptionFailure
    case downloadCouldNotMoveFile
    case downloadCouldNotDeleteFile
    case messageProcessingFailed

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { false }
}
