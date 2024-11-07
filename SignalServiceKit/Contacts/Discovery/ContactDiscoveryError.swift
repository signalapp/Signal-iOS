//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A wrapper around some of the potential errors that could be returned by a ContactDiscoveryService.
/// These could be provided by the server or the client. An error of this type will not be returned for network connectivity related reasons.
/// Usually the code doesn't matter, the accessor properties should provide the info you need.
public enum ContactDiscoveryError: Error, IsRetryableProvider, UserErrorDescriptionProvider {
    /// An error indicating that the failure was because of a rate limit
    case rateLimit(retryAfter: Date)
    /// An error indicating that the token was invalid
    case invalidToken
    /// An error that can be retried
    case retryableError(String)
    /// An error that can't be retried
    case terminalError(String)

    public var localizedDescription: String {
        OWSLocalizedString("ERROR_DESCRIPTION_SERVER_FAILURE", comment: "Generic server error")
    }

    public var isRetryableProvider: Bool {
        switch self {
        case .rateLimit(retryAfter: _): true
        case .invalidToken: true
        case .retryableError: true
        case .terminalError: false
        }
    }
}
