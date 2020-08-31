//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

fileprivate extension OWSSignalService {

    enum SignalServiceType {
        case mainSignalService
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
    }

    func signalServiceInfo(for signalServiceType: SignalServiceType) -> SignalServiceInfo {
        switch signalServiceType {
        case .mainSignalService:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.textSecureServerURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                                     requestSerializerType: .json,
                                     responseSerializerType: .json)
        }
    }

    func sessionManager(for signalServiceType: SignalServiceType) -> AFHTTPSessionManager {
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

        return sessionManager
    }

    private func sessionManagerForSignalService(censorshipConfiguration: OWSCensorshipConfiguration) -> AFHTTPSessionManager {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        let frontingURL = censorshipConfiguration.domainFrontBaseURL
        let baseUrl = frontingURL.appendingPathComponent(TSConstants.serviceCensorshipPrefix)
        let sessionManager = AFHTTPSessionManager(baseURL: baseUrl,
                                                  sessionConfiguration: sessionConfiguration)
        sessionManager.securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy
        sessionManager.requestSerializer = AFJSONRequestSerializer()
        sessionManager.responseSerializer = AFJSONResponseSerializer()
        sessionManager.requestSerializer.setValue(TSConstants.censorshipReflectorHost,
                                                  forHTTPHeaderField: "Host")
        // Disable default cookie handling for all requests.
        sessionManager.requestSerializer.httpShouldHandleCookies = false
        return sessionManager
    }

}

// MARK: -

@objc
public extension OWSSignalService {

    func sessionManagerForMainSignalService() -> AFHTTPSessionManager {
        sessionManager(for: .mainSignalService)
    }
}
