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
    func resetHasCensoredPhoneNumberFromProvisioning()

    func buildUrlEndpoint(for signalServiceInfo: SignalServiceInfo) -> OWSURLSessionEndpoint
    func buildUrlSession(
        for signalServiceInfo: SignalServiceInfo,
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration?,
        maxResponseSize: Int?,
    ) -> OWSURLSessionProtocol

    func sharedUrlSessionForCdn(
        cdnNumber: UInt32,
        maxResponseSize: UInt?,
    ) async -> OWSURLSessionProtocol
}

public enum SignalServiceType {
    case mainSignalService
    case storageService
    case updates
    case updates2
    case svr2
}

// MARK: -

public extension OWSSignalServiceProtocol {

    private func buildUrlSession(
        for signalServiceType: SignalServiceType,
        configuration: URLSessionConfiguration? = nil,
        maxResponseSize: Int? = nil,
    ) -> OWSURLSessionProtocol {
        let signalServiceInfo = signalServiceType.signalServiceInfo()
        return buildUrlSession(
            for: signalServiceInfo,
            endpoint: buildUrlEndpoint(for: signalServiceInfo),
            configuration: configuration,
            maxResponseSize: maxResponseSize,
        )
    }

    func urlSessionForMainSignalService() -> OWSURLSessionProtocol {
        buildUrlSession(for: .mainSignalService)
    }

    func urlSessionForStorageService() -> OWSURLSessionProtocol {
        buildUrlSession(for: .storageService)
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
        case .mainSignalService:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.mainServiceURL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true,
                type: self,
            )
        case .storageService:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.storageServiceURL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.storageServiceCensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: true,
                type: self,
            )
        case .updates:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.updatesURL)!,
                censorshipCircumventionSupported: false,
                censorshipCircumventionPathPrefix: "unimplemented",
                shouldUseSignalCertificate: false,
                shouldHandleRemoteDeprecation: false,
                type: self,
            )
        case .updates2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.updates2URL)!,
                censorshipCircumventionSupported: false,
                censorshipCircumventionPathPrefix: "unimplemented", // BADGES TODO
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false,
                type: self,
            )
        case .svr2:
            return SignalServiceInfo(
                baseUrl: URL(string: TSConstants.svr2URL)!,
                censorshipCircumventionSupported: true,
                censorshipCircumventionPathPrefix: TSConstants.svr2CensorshipPrefix,
                shouldUseSignalCertificate: true,
                shouldHandleRemoteDeprecation: false,
                type: self,
            )
        }
    }
}
