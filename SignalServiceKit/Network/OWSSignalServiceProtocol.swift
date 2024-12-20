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
        configuration: URLSessionConfiguration?,
        maxResponseSize: Int?
    ) -> OWSURLSessionProtocol
}

public enum SignalServiceType {
    case mainSignalServiceIdentified
    case mainSignalServiceUnidentified
    case storageService
    case cdn0
    case cdn2
    case cdn3
    case updates
    case updates2
    case svr2

    static func type(forCdnNumber cdnNumber: UInt32) -> SignalServiceType {
        switch cdnNumber {
        case 0:
            return cdn0
        case 2:
            return cdn2
        case 3:
            return cdn3
        default:
            owsFailDebug("Unrecognized CDN number configuration requested: \(cdnNumber)")
            return cdn2
        }
    }
}

// MARK: -

public extension OWSSignalServiceProtocol {

    private func buildUrlSession(
        for signalServiceType: SignalServiceType,
        configuration: URLSessionConfiguration? = nil,
        maxResponseSize: Int? = nil
    ) -> OWSURLSessionProtocol {
        let signalServiceInfo = signalServiceType.signalServiceInfo()
        return buildUrlSession(
            for: signalServiceInfo,
            endpoint: buildUrlEndpoint(for: signalServiceInfo),
            configuration: configuration,
            maxResponseSize: maxResponseSize
        )
    }

    func urlSessionForMainSignalService() -> OWSURLSessionProtocol {
        buildUrlSession(for: .mainSignalServiceIdentified)
    }

    func urlSessionForStorageService() -> OWSURLSessionProtocol {
        buildUrlSession(for: .storageService)
    }

    func urlSessionForCdn(
        cdnNumber: UInt32,
        maxResponseSize: UInt?
    ) -> OWSURLSessionProtocol {

        let urlSessionConfiguration = OWSURLSession.defaultConfigurationWithoutCaching
        urlSessionConfiguration.timeoutIntervalForRequest = 600

        return buildUrlSession(
            for: SignalServiceType.type(forCdnNumber: cdnNumber),
            configuration: urlSessionConfiguration,
            maxResponseSize: maxResponseSize.map(Int.init(clamping:))
        )
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
    let censorshipCircumventionSupported: Bool
    let censorshipCircumventionPathPrefix: String
    let shouldUseSignalCertificate: Bool
    let shouldHandleRemoteDeprecation: Bool
    let type: SignalServiceType
}

extension SignalServiceType {

    public func signalServiceInfo() -> SignalServiceInfo {
        switch self {
        case .mainSignalServiceIdentified:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.mainServiceIdentifiedURL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true,
                type: self
            )
        case .mainSignalServiceUnidentified:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.mainServiceUnidentifiedURL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true,
                type: self
            )
        case .storageService:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.storageServiceURL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.storageServiceCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true,
                type: self
            )
        case .cdn0:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.textSecureCDN0ServerURL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.cdn0CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false,
                type: self
            )
        case .cdn2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.textSecureCDN2ServerURL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.cdn2CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false,
                type: self
            )
        case .cdn3:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.textSecureCDN3ServerURL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.cdn3CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false,
                type: self
            )
        case .updates:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.updatesURL)!,
                censorshipCircumventionSupported: false,
                censorshipCircumventionPathPrefix: "unimplemented",
                shouldUseSignalCertificate: false,
                shouldHandleRemoteDeprecation: false,
                type: self
            )
        case .updates2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.updates2URL)!,
                censorshipCircumventionSupported: false,
                censorshipCircumventionPathPrefix: "unimplemented", // BADGES TODO
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false,
                type: self
            )
        case .svr2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.svr2URL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.svr2CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false,
                type: self
            )
        }
    }
}
