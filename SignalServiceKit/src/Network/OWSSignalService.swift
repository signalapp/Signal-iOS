//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

fileprivate extension OWSSignalService {

    enum SignalServiceType {
        case mainSignalService
        case storageService
        case cdn0
        case cdn2

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

    enum SerializerType {
        case json
        case binary
    }

    struct SignalServiceInfo {
        let baseUrl: URL
        let censorshipCircumventionPathPrefix: String
        let requestSerializerType: SerializerType
        let responseSerializerType: SerializerType
        let shouldHandleRemoteDeprecation: Bool
    }

    func signalServiceInfo(for signalServiceType: SignalServiceType) -> SignalServiceInfo {
        switch signalServiceType {
        case .mainSignalService:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.mainServiceURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                                     requestSerializerType: .json,
                                     responseSerializerType: .json,
                                     shouldHandleRemoteDeprecation: true)
        case .storageService:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.storageServiceURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.storageServiceCensorshipPrefix,
                                     requestSerializerType: .binary,
                                     responseSerializerType: .binary,
                                     shouldHandleRemoteDeprecation: true)
        case .cdn0:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.textSecureCDN0ServerURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.cdn0CensorshipPrefix,
                                     requestSerializerType: .binary,
                                     responseSerializerType: .binary,
                                     shouldHandleRemoteDeprecation: false)
        case .cdn2:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.textSecureCDN2ServerURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.cdn2CensorshipPrefix,
                                     requestSerializerType: .binary,
                                     responseSerializerType: .binary,
                                     shouldHandleRemoteDeprecation: false)
        }
    }

    private func buildUrlSession(for signalServiceType: SignalServiceType) -> OWSURLSession {
        let signalServiceInfo = self.signalServiceInfo(for: signalServiceType)
        let isCensorshipCircumventionActive = self.isCensorshipCircumventionActive
        let urlSession: OWSURLSession
        if isCensorshipCircumventionActive {
            let censorshipConfiguration = buildCensorshipConfiguration()
            let frontingURL = censorshipConfiguration.domainFrontBaseURL
            let baseUrl = frontingURL.appendingPathComponent(signalServiceInfo.censorshipCircumventionPathPrefix)
            let securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy
            let extraHeaders = ["Host": TSConstants.censorshipReflectorHost]
            urlSession = OWSURLSession(baseUrl: baseUrl,
                                       frontingURL: frontingURL,
                                       securityPolicy: securityPolicy,
                                       configuration: OWSURLSession.defaultConfigurationWithoutCaching,
                                       extraHeaders: extraHeaders)
        } else {
            let baseUrl = signalServiceInfo.baseUrl
            let securityPolicy = OWSHTTPSecurityPolicy.shared()
            urlSession = OWSURLSession(baseUrl: baseUrl,
                                       frontingURL: nil,
                                       securityPolicy: securityPolicy,
                                       configuration: OWSURLSession.defaultConfigurationWithoutCaching,
                                       extraHeaders: [:])
        }
        urlSession.shouldHandleRemoteDeprecation = signalServiceInfo.shouldHandleRemoteDeprecation
        return urlSession
    }
}

// MARK: -

@objc
public extension OWSSignalService {

    func urlSessionForMainSignalService() -> OWSURLSession {
        buildUrlSession(for: .mainSignalService)
    }

    func urlSessionForStorageService() -> OWSURLSession {
        buildUrlSession(for: .storageService)
    }

    @objc(urlSessionForCdnNumber:)
    func urlSessionForCdn(cdnNumber: UInt32) -> OWSURLSession {
        buildUrlSession(for: SignalServiceType.type(forCdnNumber: cdnNumber))
    }
}
