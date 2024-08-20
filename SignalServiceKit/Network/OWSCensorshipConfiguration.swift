//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum OWSFrontingHost {
    case fastly
    case googleEgypt
    case googleUae
    case googleOman
    case googleQatar
    case googleUzbekistan
    case googleVenezuela
    case `default`

    /// When using censorship circumvention, we pin to the fronted domain host.
    /// Adding a new domain front entails adding a corresponding OWSHTTPSecurityPolicy
    /// and pinning to its CA.
    /// If the security policy requires new certificates, include them in the SSK bundle
    fileprivate var securityPolicy: OWSHTTPSecurityPolicy {
        switch self {
        case .googleEgypt, .googleUae, .googleOman, .googleQatar, .googleUzbekistan, .googleVenezuela, .default:
            return PinningPolicy.google.securityPolicy
        case .fastly:
            return PinningPolicy.fastly.securityPolicy
        }
    }

    fileprivate var requiresPathPrefix: Bool {
        switch self {
        case .googleEgypt, .googleUae, .googleOman, .googleQatar, .googleUzbekistan, .googleVenezuela, .`default`:
            return true
        case .fastly:
            return false
        }
    }

    fileprivate func randomSniHeader() -> String {
        self.sniHeaders.randomElement()!
    }

    /// None of these can be empty arrays or a crash will occur in `randomSniHeader()` above.
    private var sniHeaders: [String] {
        switch self {
        case .fastly:
            Self.fastlySniHeaders
        case .googleEgypt:
            Self.googleEgyptSniHeaders
        case .googleUae:
            Self.googleOmanSniHeaders
        case .googleOman:
            Self.googleOmanSniHeaders
        case .googleQatar:
            Self.googleQatarSniHeaders
        case .googleUzbekistan:
            Self.googleUzbekistanSniHeaders
        case .googleVenezuela:
            Self.googleVenezuelaSniHeaders
        case .default:
            Self.googleCommonSniHeaders
        }
    }

    private static let fastlySniHeaders = ["github.githubassets.com", "pinterest.com", "www.redditstatic.com"]
    private static let googleCommonSniHeaders = [
        "www.google.com",
        "android.clients.google.com",
        "clients3.google.com",
        "clients4.google.com",
        "inbox.google.com"
    ]
    private static let googleEgyptSniHeaders = googleCommonSniHeaders + ["www.google.com.eg"]
    private static let googleUaeSniHeaders = googleCommonSniHeaders + ["www.google.ae"]
    private static let googleOmanSniHeaders = googleCommonSniHeaders + ["www.google.com.om"]
    private static let googleQatarSniHeaders = googleCommonSniHeaders + ["www.google.com.qa"]
    private static let googleUzbekistanSniHeaders = googleCommonSniHeaders + ["www.google.co.uz"]
    private static let googleVenezuelaSniHeaders = googleCommonSniHeaders + ["www.google.co.ve"]
}

struct OWSCensorshipConfiguration {

    let domainFrontBaseUrl: URL
    let domainFrontSecurityPolicy: OWSHTTPSecurityPolicy
    let requiresPathPrefix: Bool

    /// Returns a service specific host header.
    ///
    /// Callers should use a default host header if there's not a service specific host header.
    func hostHeader(_ signalServiceType: SignalServiceType) -> String? {
        // right now we either have different host headers or path prefixes but not both
        if requiresPathPrefix {
            return nil
        } else {
            switch signalServiceType {
            case .mainSignalServiceIdentified, .mainSignalServiceUnidentified:
                return "chat-signal.global.ssl.fastly.net"
            case .storageService:
                return "storage.signal.org.global.prod.fastly.net"
            case .cdn0:
                return "cdn.signal.org.global.prod.fastly.net"
            case .cdn2:
                return "cdn2.signal.org.global.prod.fastly.net"
            case .cdn3:
                return "cdn3-signal.global.ssl.fastly.net"
            case .updates, .updates2:
                return nil
            case .contactDiscoveryV2:
                return "cdsi-signal.global.ssl.fastly.net"
            case .svr2:
                return "svr2-signal.global.ssl.fastly.net"
            }
        }
    }

    /// Returns `nil` if `e164` is not known to be censored.
    static func censorshipConfiguration(e164: String) -> OWSCensorshipConfiguration? {
        guard let countryCode = censoredCountryCode(e164: e164) else {
            return nil
        }

        return censorshipConfiguration(countryCode: countryCode)
    }

    /// Returns the best censorship configuration for `countryCode`. Will return a default if one
    /// hasn't been specifically configured.
    static func censorshipConfiguration(countryCode: String) -> OWSCensorshipConfiguration {
        let countryMetadata = OWSCountryMetadata.countryMetadata(countryCode: countryCode)
        guard let specifiedDomain = countryMetadata?.frontingDomain else {
            return defaultConfiguration
        }

        let sniHeader = specifiedDomain.randomSniHeader()
        guard let baseUrl = URL(string: "https://\(sniHeader)") else {
            owsFailDebug("baseUrl was unexpectedly nil with specifiedDomain: \(sniHeader)")
            return defaultConfiguration
        }

        return OWSCensorshipConfiguration(domainFrontBaseUrl: baseUrl, securityPolicy: specifiedDomain.securityPolicy, requiresPathPrefix: specifiedDomain.requiresPathPrefix)
    }

    static var defaultConfiguration: OWSCensorshipConfiguration {
        let baseUrl = URL(string: "https://\(OWSFrontingHost.default.randomSniHeader())")!
        return OWSCensorshipConfiguration(domainFrontBaseUrl: baseUrl, securityPolicy: OWSFrontingHost.default.securityPolicy, requiresPathPrefix: OWSFrontingHost.default.requiresPathPrefix)

    }

    static func isCensored(e164: String) -> Bool {
        censoredCountryCode(e164: e164) != nil
    }

    private init(domainFrontBaseUrl: URL, securityPolicy: OWSHTTPSecurityPolicy, requiresPathPrefix: Bool) {
        self.domainFrontBaseUrl = domainFrontBaseUrl
        self.domainFrontSecurityPolicy = securityPolicy
        self.requiresPathPrefix = requiresPathPrefix
    }

    /// The set of countries for which domain fronting should be automatically enabled.
    ///
    /// If you want to use a domain front other than the default, specify the domain front
    /// in OWSCountryMetadata, and ensure we have a Security Policy for that domain in
    /// `securityPolicyForDomain:`
    private static let censoredCountryCodes: [String: String] = [
        // Egypt
        "+20": "EG",
        // Oman
        "+968": "OM",
        // Qatar
        "+974": "QA",
        // UAE
        "+971": "AE",
        // Cuba
        "+53": "CU",
        // Venezuela
        "+58": "VE",
        // Uzbekistan,
        "+998": "UZ",
        // Russia
        "+7": "RU",
    ]

    /// Returns nil if the phone number is not known to be censored
    private static func censoredCountryCode(e164: String) -> String? {
        for (key: callingCode, value: countryCode) in censoredCountryCodes {
            if e164.hasPrefix(callingCode) {
                return countryCode
            }
        }

        return nil
    }
}

private enum PinningPolicy {
    case fastly
    case google

    var securityPolicy: OWSHTTPSecurityPolicy {
        switch self {
        case .fastly:
            return Self.fastlySecurityPolicy
        case .google:
            return Self.googleSecurityPolicy
        }
    }

    private static func securityPolicy(certNames: [String]) -> OWSHTTPSecurityPolicy {
        var certificates = Set<Data>()
        for certName in certNames {
            certificates.insert(certificateData(name: certName))
        }
        return OWSHTTPSecurityPolicy(pinnedCertificates: certificates)
    }

    private static func certificateData(name: String) -> Data {
        guard !name.isEmpty else {
            owsFail("expected name with length > 0")
        }

        let bundle = Bundle(for: OWSHTTPSecurityPolicy.self)
        guard let url = bundle.url(forResource: name, withExtension: "crt") else {
            owsFail("missing certificate data for name: \(name)")
        }

        do {
            let certData = try Data(contentsOf: url)
            guard !certData.isEmpty else {
                owsFail("empty certData for name: \(name)")
            }
            return certData
        } catch {
            owsFail("failed to read cert file with path: \(url)")
        }
    }

    private static let fastlySecurityPolicy = OWSHTTPSecurityPolicy.systemDefault()

    private static let googleSecurityPolicy = {
        // GIAG2 cert plus root certs from pki.goog
        securityPolicy(certNames: ["GIAG2", "GSR2", "GSR4", "GTSR1", "GTSR2", "GTSR3", "GTSR4"])
    }()
}
