//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol OWSSignalServiceProtocol: AnyObject {
    func warmCaches()

    // MARK: - Censorship Circumvention

    var isCensorshipCircumventionActive: Bool { get }
    var hasCensoredPhoneNumber: Bool { get }
    var isCensorshipCircumventionManuallyActivated: Bool { get set }
    var isCensorshipCircumventionManuallyDisabled: Bool { get set }
    var manualCensorshipCircumventionCountryCode: String? { get set }

    func updateHasCensoredPhoneNumberDuringProvisioning(_ e164: E164)

    func buildUrlEndpoint(for signalServiceInfo: SignalServiceInfo) -> OWSURLSessionEndpoint
    func buildUrlSession(
        for signalServiceInfo: SignalServiceInfo,
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration?
    ) -> OWSURLSessionProtocol
}

public enum SignalServiceType {
    case mainSignalServiceIdentified
    case mainSignalServiceUnidentified
    case storageService
    case cdn0
    case cdn2
    case kbs
    case updates
    case updates2
    case contactDiscoveryV2
    case svr2

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
            endpoint: buildUrlEndpoint(for: signalServiceInfo),
            configuration: nil
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
        case .svr2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.svr2URL)!,
                censorshipCircumventionPathPrefix: TSConstants.svr2CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false
            )
        }
    }
}
