//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Security

/// A simplified version of AFNetworking's AFSecurityPolicy.
public struct HttpSecurityPolicy {
    public static let signalCaPinned: HttpSecurityPolicy = .init(pinnedCertificates: [Certificates.load("signal-messenger", extension: "cer")])
    public static let systemDefault: HttpSecurityPolicy = .init()

    private let pinnedCertificates: [SecCertificate]?

    public init(pinnedCertificates: [SecCertificate]? = nil) {
        self.pinnedCertificates = pinnedCertificates
    }

    public func evaluate(serverTrust: SecTrust, domain: String?) -> Bool {
        let policies = [SecPolicyCreateSSL(true, domain as CFString?)]

        guard SecTrustSetPolicies(serverTrust, policies as CFArray) == errSecSuccess else {
            Logger.error("the trust policy could not be set")
            return false
        }

        // use the default anchors if none were prvided in pinnedCertificates
        if let pinnedCertificates, !pinnedCertificates.isEmpty {
            guard SecTrustSetAnchorCertificates(serverTrust, pinnedCertificates as CFArray) == errSecSuccess else {
                Logger.error("the anchor certificates could not be set")
                return false
            }
        }

        return Self.isValid(serverTrust: serverTrust)
    }

    private static func isValid(serverTrust: SecTrust) -> Bool {
        guard SecTrustEvaluateWithError(serverTrust, nil) else {
            return false
        }
        var result: SecTrustResultType = .otherError  // initialize to a value that would fail if SecTrustGetTrustResult doesn't overwrite it
        guard SecTrustGetTrustResult(serverTrust, &result) == errSecSuccess else {
            return false
        }
        return result == .unspecified || result == .proceed
    }
}
