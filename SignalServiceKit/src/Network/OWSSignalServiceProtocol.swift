//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol OWSSignalServiceProtocol: AnyObject {
    @objc
    var keyValueStore: SDSKeyValueStore { get }

    @objc
    func warmCaches()

    // MARK: - Censorship Circumvention

    @objc
    var isCensorshipCircumventionActive: Bool { get }
    @objc
    var hasCensoredPhoneNumber: Bool { get }
    @objc
    var isCensorshipCircumventionManuallyActivated: Bool { get set }
    @objc
    var isCensorshipCircumventionManuallyDisabled: Bool { get set }
    @objc
    var manualCensorshipCircumventionCountryCode: String? { get set }

    /// should only be accessed if censorship circumvention is active.
    @objc
    var domainFrontBaseURL: URL { get }

    @objc
    func buildCensorshipConfiguration() -> OWSCensorshipConfiguration

    // The _real types here can't be exposed to objc, but this protocol must be exposed,
    // so do a not-type-safe thing to enforce that all implemetors must implement this.
    func typeUnsafe_buildUrlSession(for signalServiceType: Any) -> Any
}

extension OWSSignalServiceProtocol {

    public func buildUrlSession(for signalServiceType: SignalServiceType) -> OWSURLSessionProtocol {
        return typeUnsafe_buildUrlSession(for: signalServiceType) as! OWSURLSessionProtocol
    }
}

public enum SignalServiceType {
    case mainSignalService
    case storageService
    case cdn0
    case cdn2
    case cds(host: String, censorshipCircumventionPrefix: String)
    case remoteAttestation(host: String, censorshipCircumventionPrefix: String)
    case kbs
    case updates
    case updates2

    static func type(forCdnNumber cdnNumber: UInt32) -> SignalServiceType {
        switch cdnNumber {
        case 0:
            return cdn0
        case 2:
            return cdn2
        default:
            owsFailDebug("Unrecognized CDN number configuration requested: \(cdnNumber)")
            return cdn2
        }
    }
}

// MARK: -

public extension OWSSignalServiceProtocol {

    func urlSessionForMainSignalService() -> OWSURLSessionProtocol {
        buildUrlSession(for: .mainSignalService)
    }

    func urlSessionForStorageService() -> OWSURLSessionProtocol {
        buildUrlSession(for: .storageService)
    }

    func urlSessionForCdn(cdnNumber: UInt32) -> OWSURLSessionProtocol {
        buildUrlSession(for: SignalServiceType.type(forCdnNumber: cdnNumber))
    }

    func urlSessionForCds(
        host: String,
        censorshipCircumventionPrefix: String
    ) -> OWSURLSessionProtocol {
        buildUrlSession(
            for: .cds(
                host: host,
                censorshipCircumventionPrefix: censorshipCircumventionPrefix
            )
        )
    }

    func urlSessionForRemoteAttestation(
        host: String,
        censorshipCircumventionPrefix: String
    ) -> OWSURLSessionProtocol {
        buildUrlSession(
            for: .remoteAttestation(
                host: host,
                censorshipCircumventionPrefix: censorshipCircumventionPrefix
            )
        )
    }

    func urlSessionForKBS() -> OWSURLSessionProtocol {
        buildUrlSession(for: .kbs)
    }

    func urlSessionForUpdates() -> OWSURLSessionProtocol {
        buildUrlSession(for: .updates)
    }

    func urlSessionForUpdates2() -> OWSURLSessionProtocol {
        buildUrlSession(for: .updates2)
    }
}

// MARK: - Service type mapping

public struct SignalServiceInfo {
    let baseUrl: URL
    let censorshipCircumventionPathPrefix: String
    let shouldHandleRemoteDeprecation: Bool
}

extension SignalServiceType {

    public func signalServiceInfo() -> SignalServiceInfo {
        switch self {
        case .mainSignalService:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.mainServiceURL)!,
                censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                shouldHandleRemoteDeprecation: true
            )
        case .storageService:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.storageServiceURL)!,
                censorshipCircumventionPathPrefix: TSConstants.storageServiceCensorshipPrefix,
                shouldHandleRemoteDeprecation: true)
        case .cdn0:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.textSecureCDN0ServerURL)!,
                censorshipCircumventionPathPrefix: TSConstants.cdn0CensorshipPrefix,
                shouldHandleRemoteDeprecation: false)
        case .cdn2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.textSecureCDN2ServerURL)!,
                censorshipCircumventionPathPrefix: TSConstants.cdn2CensorshipPrefix,
                shouldHandleRemoteDeprecation: false)
        case .cds(let host, let censorshipCircumventionPrefix):
            return SignalServiceInfo(
                baseUrl: URL(string: host)!,
                censorshipCircumventionPathPrefix: censorshipCircumventionPrefix,
                shouldHandleRemoteDeprecation: false)
        case .remoteAttestation(let host, let censorshipCircumventionPrefix):
            return SignalServiceInfo(
                baseUrl: URL(string: host)!,
                censorshipCircumventionPathPrefix: censorshipCircumventionPrefix,
                shouldHandleRemoteDeprecation: false)
        case .kbs:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.keyBackupURL)!,
                censorshipCircumventionPathPrefix: TSConstants.keyBackupCensorshipPrefix,
                shouldHandleRemoteDeprecation: true)
        case .updates:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.updatesURL)!,
                censorshipCircumventionPathPrefix: "unimplemented",
                shouldHandleRemoteDeprecation: false)
        case .updates2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.updates2URL)!,
                censorshipCircumventionPathPrefix: "unimplemented", // BADGES TODO
                shouldHandleRemoteDeprecation: false)
        }
    }
}
