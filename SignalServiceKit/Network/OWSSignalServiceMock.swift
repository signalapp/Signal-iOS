//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class OWSSignalServiceMock: OWSSignalServiceProtocol {
    public func warmCaches() {}

    public var isCensorshipCircumventionActive: Bool = false

    public var hasCensoredPhoneNumber: Bool = false

    public var isCensorshipCircumventionManuallyActivated: Bool = false

    public var isCensorshipCircumventionManuallyDisabled: Bool = false

    public var manualCensorshipCircumventionCountryCode: String?

    public func updateHasCensoredPhoneNumberDuringProvisioning(_ e164: E164) {}
    public func resetHasCensoredPhoneNumberFromProvisioning() {}

    public var urlEndpointBuilder: ((SignalServiceInfo) -> OWSURLSessionEndpoint)?

    public func buildUrlEndpoint(for signalServiceInfo: SignalServiceInfo) -> OWSURLSessionEndpoint {
        return urlEndpointBuilder?(signalServiceInfo) ?? OWSURLSessionEndpoint(
            baseUrl: signalServiceInfo.baseUrl,
            frontingInfo: nil,
            securityPolicy: .systemDefault,
            extraHeaders: [:],
        )
    }

    public var mockUrlSessionBuilder: ((SignalServiceInfo, OWSURLSessionEndpoint, URLSessionConfiguration?) -> BaseOWSURLSessionMock)?

    public func buildUrlSession(
        for signalServiceInfo: SignalServiceInfo,
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration?,
        maxResponseSize: Int?,
    ) -> OWSURLSessionProtocol {
        return mockUrlSessionBuilder?(signalServiceInfo, endpoint, configuration) ?? BaseOWSURLSessionMock(
            endpoint: endpoint,
            configuration: .default,
            maxResponseSize: maxResponseSize,
        )
    }

    public var mockCDNUrlSessionBuilder: ((_ cdnNumber: UInt32) -> BaseOWSURLSessionMock)?

    public func sharedUrlSessionForCdn(
        cdnNumber: UInt32,
        maxResponseSize: UInt?,
    ) async -> OWSURLSessionProtocol {
        let baseUrl: URL
        switch cdnNumber {
        case 0:
            baseUrl = URL(string: TSConstants.textSecureCDN0ServerURL)!
        case 3:
            baseUrl = URL(string: TSConstants.textSecureCDN3ServerURL)!
        default:
            baseUrl = URL(string: TSConstants.textSecureCDN2ServerURL)!
        }

        return mockCDNUrlSessionBuilder?(cdnNumber) ?? BaseOWSURLSessionMock(
            endpoint: OWSURLSessionEndpoint(
                baseUrl: baseUrl,
                frontingInfo: nil,
                securityPolicy: .systemDefault,
                extraHeaders: [:],
            ),
            configuration: .default,
            maxResponseSize: maxResponseSize.map(Int.init(clamping:)),
        )
    }
}

#endif
