//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

struct DiscoveredContactInfo: Hashable {
    let e164: String?
    let uuid: UUID?         // This should be made non-optional when we drop Legacy CDS
}

/// An item that fetches contact info from the ContactDiscoveryService
/// Intended to be used by ContactDiscoveryTask. You probably don't want to use this directly.
protocol ContactDiscovering {
    /// Constructs a ContactDiscovering object from a set of e164 phone numbers
    init(phoneNumbersToLookup: Set<String>)

    /// Returns a promise that performs ContactDiscovery on the provided queue
    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>>
}

/// A wrapper around some of the potential errors that could be returned by a ContactDiscoveryService.
/// These could be provided by the server or the client. An error of this type will not be returned for network connectivity related reasons.
/// Usually the code doesn't matter, the accessor properties should provide the info you need.
public struct ContactDiscoveryError: Error {

    /// The reason for the error. You probably don't need to consult this directly.
    public let kind: Kind

    /// Loggable description of the error
    public let debugDescription: String?

    /// Whether or not it's suggested you retry the discovery task.
    /// This is hardcoded based on server suggestions on what errors are retryable.
    ///
    /// There are cases where an error may be marked as unretryable, but still have a retryAfterDate provided
    /// This is because the retryable flag is more of a server suggestion, where retryAfter is a server requirement.
    public let retryable: Bool

    /// Provided by the server. Clients should make every effort to respect the retryAfterDate.
    public let retryAfterDate: Date?


    // MARK: - Constructors

    static func assertionError(description: String) -> ContactDiscoveryError {
        return ContactDiscoveryError(kind: .assertion, debugDescription: description, retryable: false, retryAfterDate: nil)
    }

    static func rateLimit(expiryDate: Date) -> ContactDiscoveryError {
        return ContactDiscoveryError(kind: .rateLimit, debugDescription: "Rate Limited", retryable: true, retryAfterDate: expiryDate)
    }

    // MARK: - Variants

    public enum Kind: Int, RawRepresentable {
        case generic = 1
        case assertion

        /// An error indicating that the current user has an expired auth token
        case unauthorized
        /// An error indicating that a hardcoded resource is unavailable. Best recourse is to update the app.
        case unexpectedResponse
        /// An error indicating response timeout.
        case timeout
        /// An error indicating that the failure was because of a rate limit
        case rateLimit

        /// Any generic 4xx error that doesn't fit in the above categories
        case genericClientError
        /// Any generic 5xx error that doesn't fit in the above categories
        case genericServerError
    }
}
