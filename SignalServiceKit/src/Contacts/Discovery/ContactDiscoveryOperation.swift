//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct DiscoveredContactInfo: Hashable {
    let e164: E164
    let uuid: UUID
}

/// An item that fetches contact info from the ContactDiscoveryService
/// Intended to be used by ContactDiscoveryTaskQueue. You probably don't want to use this directly.
protocol ContactDiscoveryOperation {
    init(e164sToLookup: Set<E164>, mode: ContactDiscoveryMode)
    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>>
}

/// A wrapper around some of the potential errors that could be returned by a ContactDiscoveryService.
/// These could be provided by the server or the client. An error of this type will not be returned for network connectivity related reasons.
/// Usually the code doesn't matter, the accessor properties should provide the info you need.
@objc(OWSContactDiscoveryError)
public class ContactDiscoveryError: NSError, UserErrorDescriptionProvider {
    static let domain: String = "ContactDiscoveryErrorDomain"

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
    @objc
    public let retrySuggested: Bool

    /// Provided by the server. Clients should make every effort to respect the retryAfterDate.
    @objc
    public let retryAfterDate: Date?

    // MARK: - Constructors

    static func assertionError(description: String) -> ContactDiscoveryError {
        owsFailDebug(description)

        return ContactDiscoveryError(
            kind: .assertion,
            debugDescription: description,
            retryable: false,
            retryAfterDate: nil
        )
    }

    init(kind: Kind, debugDescription: String, retryable: Bool, retryAfterDate: Date?) {
        self.retrySuggested = retryable
        self.retryAfterDate = retryAfterDate

        super.init(domain: Self.domain, code: kind.rawValue, userInfo: [
            NSDebugDescriptionErrorKey: debugDescription
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        OWSLocalizedString("ERROR_DESCRIPTION_SERVER_FAILURE", comment: "Generic server error")
    }
}

// MARK: - ContactDiscoveryError

extension ContactDiscoveryError: IsRetryableProvider {
    public var isRetryableProvider: Bool {
        retrySuggested
    }
}

struct ContactDiscoveryE164Collection<T: Collection> where T.Element == E164 {
    let values: T
    let encodedValues: Data

    init(_ e164s: T) {
        self.values = e164s
        self.encodedValues = Self.buildEncodedValues(for: e164s)
    }

    private static func buildEncodedValues(for e164s: T) -> Data {
        var result = Data()
        result.reserveCapacity(MemoryLayout<UInt64>.size * e164s.count)
        return e164s.reduce(into: result) { $0.append($1.uint64Value.bigEndianData) }
    }
}
