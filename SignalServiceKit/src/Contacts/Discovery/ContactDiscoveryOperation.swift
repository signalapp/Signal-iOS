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
    init(e164sToLookup: Set<String>)

    /// Returns a promise that performs ContactDiscovery on the provided queue
    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>>
}

/// A wrapper around some of the potential errors that could be returned by a ContactDiscoveryService.
/// These could be provided by the server or the client. An error of this type will not be returned for network connectivity related reasons.
/// Usually the code doesn't matter, the accessor properties should provide the info you need.
@objc(OWSContactDiscoveryError)
public class ContactDiscoveryError: NSError {
    static let domain: String = "ContactDiscoveryErrorDomain"
    static let maxRetryAfterInterval = 60 * kMinuteInterval

    /// The reason for the error. You probably don't need to consult this directly.
    public var kind: Kind {
        guard let kind = Kind(rawValue: code) else {
            owsFailDebug("Invalid error code")
            return .generic
        }
        return kind
    }

    /// Whether or not it's suggested you retry the discovery task.
    /// This is hardcoded based on server suggestions on what errors are retryable.
    ///
    /// There are cases where an error may be marked as unretryable, but still have a retryAfterDate provided
    /// This is because the retryable flag is more of a server suggestion, where retryAfter is a server requirement.
    @objc public let retrySuggested: Bool

    /// Provided by the server. Clients should make every effort to respect the retryAfterDate.
    @objc public let retryAfterDate: Date?

    // MARK: - Constructors

    static func assertionError(description: String) -> ContactDiscoveryError {
        owsFailDebug(description)

        return ContactDiscoveryError(
            kind: .assertion,
            debugDescription: description,
            retryable: false,
            retryAfterDate: nil)
    }

    static func rateLimit(expiryDate: Date) -> ContactDiscoveryError {
        return ContactDiscoveryError(
            kind: .rateLimit,
            debugDescription: "Rate Limited",
            retryable: true,
            retryAfterDate: expiryDate)
    }

    init(kind: Kind, debugDescription: String, retryable: Bool, retryAfterDate: Date?) {
        self.retrySuggested = retryable
        if let retryAfterDate = retryAfterDate {
            self.retryAfterDate = min(retryAfterDate, Date(timeIntervalSinceNow: Self.maxRetryAfterInterval))
        } else {
            self.retryAfterDate = nil
        }

        super.init(domain: Self.domain, code: kind.rawValue, userInfo: [
            NSDebugDescriptionErrorKey: debugDescription
        ])
    }

    required init?(coder: NSCoder) {
        notImplemented()
    }

    // MARK: - Variants

    @objc(OWSContactDiscoveryErrorCode)
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

    public override var localizedDescription: String {
        NSLocalizedString("ERROR_DESCRIPTION_SERVER_FAILURE", comment: "Generic server error")
    }
}
