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

    // The _real types here can't be exposed to objc, but this protocol must be exposed,
    // so do a not-type-safe thing to enforce that all implemetors must implement this.
    func typeUnsafe_buildUrlEndpoint(for signalServiceInfo: Any) -> Any
    func typeUnsafe_buildUrlSession(
        for signalServiceInfo: Any,
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration?
    ) -> Any
}

extension OWSSignalServiceProtocol {
    public func buildUrlEndpoint(for signalServiceType: SignalServiceInfo) -> OWSURLSessionEndpoint {
        return typeUnsafe_buildUrlEndpoint(for: signalServiceType) as! OWSURLSessionEndpoint
    }

    public func buildUrlSession(
        for signalServiceInfo: SignalServiceInfo,
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration? = nil
    ) -> OWSURLSessionProtocol {
        return typeUnsafe_buildUrlSession(
            for: signalServiceInfo,
            endpoint: endpoint,
            configuration: configuration
        ) as! OWSURLSessionProtocol
    }
}

public enum SignalServiceType {
    case mainSignalServiceIdentified
    case mainSignalServiceUnidentified
    case storageService
    case cdn0
    case cdn2
    case cds(host: String, censorshipCircumventionPrefix: String)
    case remoteAttestation(host: String, censorshipCircumventionPrefix: String)
    case kbs
    case updates
    case updates2
    case contactDiscoveryV2

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

    private func buildUrlSession(for signalServiceType: SignalServiceType) -> OWSURLSessionProtocol {
        let signalServiceInfo = signalServiceType.signalServiceInfo()
        return buildUrlSession(
            for: signalServiceInfo,
            endpoint: buildUrlEndpoint(for: signalServiceInfo)
        )
    }

    func urlSessionForMainSignalService() -> OWSURLSessionProtocol {
        buildUrlSession(for: .mainSignalServiceIdentified)
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
    let shouldUseSignalCertificate: Bool
    let shouldHandleRemoteDeprecation: Bool
}

extension SignalServiceType {

    public func signalServiceInfo() -> SignalServiceInfo {
        switch self {
        case .mainSignalServiceIdentified:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.mainServiceIdentifiedURL)!,
                censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true
            )
        case .mainSignalServiceUnidentified:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.mainServiceUnidentifiedURL)!,
                censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true
            )
        case .storageService:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.storageServiceURL)!,
                censorshipCircumventionPathPrefix: TSConstants.storageServiceCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true
            )
        case .cdn0:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.textSecureCDN0ServerURL)!,
                censorshipCircumventionPathPrefix: TSConstants.cdn0CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false
            )
        case .cdn2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.textSecureCDN2ServerURL)!,
                censorshipCircumventionPathPrefix: TSConstants.cdn2CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false
            )
        case .cds(let host, let censorshipCircumventionPrefix):
            return SignalServiceInfo(
                baseUrl: URL(string: host)!,
                censorshipCircumventionPathPrefix: censorshipCircumventionPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false
            )
        case .remoteAttestation(let host, let censorshipCircumventionPrefix):
            return SignalServiceInfo(
                baseUrl: URL(string: host)!,
                censorshipCircumventionPathPrefix: censorshipCircumventionPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false
            )
        case .kbs:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.keyBackupURL)!,
                censorshipCircumventionPathPrefix: TSConstants.keyBackupCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true
            )
        case .updates:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.updatesURL)!,
                censorshipCircumventionPathPrefix: "unimplemented",
                shouldUseSignalCertificate: false,
                shouldHandleRemoteDeprecation: false
            )
        case .updates2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.updates2URL)!,
                censorshipCircumventionPathPrefix: "unimplemented", // BADGES TODO
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false
            )
        case .contactDiscoveryV2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.contactDiscoveryV2URL)!,
                censorshipCircumventionPathPrefix: TSConstants.contactDiscoveryV2CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false
            )
        }
    }
}
