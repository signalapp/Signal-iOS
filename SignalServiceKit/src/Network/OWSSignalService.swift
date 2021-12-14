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

    enum SerializerType {
        case json
        case binary
    }

    struct SignalServiceInfo {
        let baseUrl: URL
        let censorshipCircumventionPathPrefix: String
        let shouldHandleRemoteDeprecation: Bool
    }

    func signalServiceInfo(for signalServiceType: SignalServiceType) -> SignalServiceInfo {
        switch signalServiceType {
        case .mainSignalService:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.mainServiceURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.serviceCensorshipPrefix,
                                     shouldHandleRemoteDeprecation: true)
        case .storageService:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.storageServiceURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.storageServiceCensorshipPrefix,
                                     shouldHandleRemoteDeprecation: true)
        case .cdn0:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.textSecureCDN0ServerURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.cdn0CensorshipPrefix,
                                     shouldHandleRemoteDeprecation: false)
        case .cdn2:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.textSecureCDN2ServerURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.cdn2CensorshipPrefix,
                                     shouldHandleRemoteDeprecation: false)
        case .cds(let host, let censorshipCircumventionPrefix):
            return SignalServiceInfo(baseUrl: URL(string: host)!,
                                     censorshipCircumventionPathPrefix: censorshipCircumventionPrefix,
                                     shouldHandleRemoteDeprecation: false)
        case .remoteAttestation(let host, let censorshipCircumventionPrefix):
            return SignalServiceInfo(baseUrl: URL(string: host)!,
                                     censorshipCircumventionPathPrefix: censorshipCircumventionPrefix,
                                     shouldHandleRemoteDeprecation: false)
        case .kbs:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.keyBackupURL)!,
                                     censorshipCircumventionPathPrefix: TSConstants.keyBackupCensorshipPrefix,
                                     shouldHandleRemoteDeprecation: true)
        case .updates:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.updatesURL)!,
                                     censorshipCircumventionPathPrefix: "unimplemented",
                                     shouldHandleRemoteDeprecation: false)
        case .updates2:
            return SignalServiceInfo(baseUrl: URL(string: TSConstants.updates2URL)!,
                                     censorshipCircumventionPathPrefix: "unimplemented", // BADGES TODO
                                     shouldHandleRemoteDeprecation: false)
        }
    }

    private func buildUrlSession(for signalServiceType: SignalServiceType) -> OWSURLSession {
        let signalServiceInfo = self.signalServiceInfo(for: signalServiceType)
        let isCensorshipCircumventionActive = self.isCensorshipCircumventionActive
        let urlSession: OWSURLSession
        if isCensorshipCircumventionActive {
            let censorshipConfiguration = buildCensorshipConfiguration()
            let frontingURLWithoutPathPrefix = censorshipConfiguration.domainFrontBaseURL
            let frontingPathPrefix = signalServiceInfo.censorshipCircumventionPathPrefix
            let frontingURLWithPathPrefix = frontingURLWithoutPathPrefix.appendingPathComponent(frontingPathPrefix)
            let unfrontedBaseUrl = signalServiceInfo.baseUrl
            let frontingInfo = OWSURLSession.FrontingInfo(frontingURLWithoutPathPrefix: frontingURLWithoutPathPrefix,
                                                          frontingURLWithPathPrefix: frontingURLWithPathPrefix,
                                                          unfrontedBaseUrl: unfrontedBaseUrl)
            let baseUrl = frontingURLWithPathPrefix
            let securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy
            let extraHeaders = ["Host": TSConstants.censorshipReflectorHost]
            urlSession = OWSURLSession(baseUrl: baseUrl,
                                       frontingInfo: frontingInfo,
                                       securityPolicy: securityPolicy,
                                       configuration: OWSURLSession.defaultConfigurationWithoutCaching,
                                       extraHeaders: extraHeaders)
        } else {
            let baseUrl = signalServiceInfo.baseUrl
            let securityPolicy: OWSHTTPSecurityPolicy
            switch signalServiceType {
            case .updates:
                securityPolicy = OWSURLSession.defaultSecurityPolicy
            default:
                securityPolicy = OWSURLSession.signalServiceSecurityPolicy
            }
            urlSession = OWSURLSession(baseUrl: baseUrl,
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

    func urlSessionForCds(host: String,
                          censorshipCircumventionPrefix: String) -> OWSURLSession {
        buildUrlSession(for: .cds(host: host,
                                  censorshipCircumventionPrefix: censorshipCircumventionPrefix))
    }

    func urlSessionForRemoteAttestation(host: String,
                                        censorshipCircumventionPrefix: String) -> OWSURLSession {
        buildUrlSession(for: .remoteAttestation(host: host,
                                                censorshipCircumventionPrefix: censorshipCircumventionPrefix))
    }

    func urlSessionForKBS() -> OWSURLSession {
        buildUrlSession(for: .kbs)
    }

    func urlSessionForUpdates() -> OWSURLSession {
        buildUrlSession(for: .updates)
    }

    func urlSessionForUpdates2() -> OWSURLSession {
        buildUrlSession(for: .updates2)
    }
}
