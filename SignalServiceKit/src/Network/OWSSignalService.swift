//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.textSecureServerURL)!,
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

    func buildSessionManager(for signalServiceType: SignalServiceType) -> AFHTTPSessionManager {
        let signalServiceInfo = self.signalServiceInfo(for: signalServiceType)
        let isCensorshipCircumventionActive = self.isCensorshipCircumventionActive
        let baseUrl: URL
        let securityPolicy: AFSecurityPolicy
        if isCensorshipCircumventionActive {
            let censorshipConfiguration = buildCensorshipConfiguration()
            let frontingURL = censorshipConfiguration.domainFrontBaseURL
            baseUrl = frontingURL.appendingPathComponent(signalServiceInfo.censorshipCircumventionPathPrefix)
            securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy
        } else {
            baseUrl = signalServiceInfo.baseUrl
            securityPolicy = OWSHTTPSecurityPolicy.shared()
        }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        let sessionManager = AFHTTPSessionManager(baseURL: baseUrl,
                                                  sessionConfiguration: sessionConfiguration)
        sessionManager.securityPolicy = securityPolicy

        switch signalServiceInfo.requestSerializerType {
        case .json:
            sessionManager.requestSerializer = AFJSONRequestSerializer()
        case .binary:
            sessionManager.requestSerializer = AFHTTPRequestSerializer()
        }
        switch signalServiceInfo.responseSerializerType {
        case .json:
            sessionManager.responseSerializer = AFJSONResponseSerializer()
        case .binary:
            sessionManager.responseSerializer = AFHTTPResponseSerializer()
        }

        // Disable default cookie handling for all requests.
        sessionManager.requestSerializer.httpShouldHandleCookies = false
        if isCensorshipCircumventionActive {
            sessionManager.requestSerializer.setValue(TSConstants.censorshipReflectorHost,
                                                      forHTTPHeaderField: "Host")
        }

        if signalServiceType == .cdn0 {
            // Default acceptable content headers are rejected by AWS
            sessionManager.responseSerializer.acceptableContentTypes = nil
        }

        return sessionManager
    }

    private func buildUrlSession(for signalServiceType: SignalServiceType) -> OWSURLSession {
        let signalServiceInfo = self.signalServiceInfo(for: signalServiceType)
        let isCensorshipCircumventionActive = self.isCensorshipCircumventionActive
        let baseUrl: URL
        let censorshipCircumventionHost: String?
        let securityPolicy: AFSecurityPolicy
        let extraHeaders: [String: String]
        if isCensorshipCircumventionActive {
            let censorshipConfiguration = buildCensorshipConfiguration()
            let frontingURL = censorshipConfiguration.domainFrontBaseURL
            baseUrl = frontingURL.appendingPathComponent(signalServiceInfo.censorshipCircumventionPathPrefix)
            securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy
            censorshipCircumventionHost = signalServiceInfo.baseUrl.host
            extraHeaders = ["Host": TSConstants.censorshipReflectorHost]
        } else {
            baseUrl = signalServiceInfo.baseUrl
            securityPolicy = OWSHTTPSecurityPolicy.shared()
            censorshipCircumventionHost = nil
            extraHeaders = [:]
        }

        let urlSession = OWSURLSession(baseUrl: baseUrl,
                                       securityPolicy: securityPolicy,
                                       configuration: .ephemeral,
                                       censorshipCircumventionHost: censorshipCircumventionHost,
                                       extraHeaders: extraHeaders)
        urlSession.shouldHandleRemoteDeprecation = signalServiceInfo.shouldHandleRemoteDeprecation
        return urlSession
    }
}

// MARK: -

@objc
public extension OWSSignalService {

    // TODO: Remove in favor of OWSURLSession.
    func sessionManagerForMainSignalService() -> AFHTTPSessionManager {
        buildSessionManager(for: .mainSignalService)
    }

    // TODO: Remove in favor of OWSURLSession.
    @objc(sessionManagerForCdnNumber:)
    func sessionManagerForCdn(cdnNumber: UInt32) -> AFHTTPSessionManager {
        buildSessionManager(for: SignalServiceType.type(forCdnNumber: cdnNumber))
    }

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
