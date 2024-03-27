//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class OWSSignalServiceMock: OWSSignalServiceProtocol, Dependencies {
    public func warmCaches() {}

    public var isCensorshipCircumventionActive: Bool = false

    public var hasCensoredPhoneNumber: Bool = false

    public var isCensorshipCircumventionManuallyActivated: Bool = false

    public var isCensorshipCircumventionManuallyDisabled: Bool = false

    public var manualCensorshipCircumventionCountryCode: String?

    public func updateHasCensoredPhoneNumberDuringProvisioning(_ e164: E164) {}

    public var urlEndpointBuilder: ((SignalServiceInfo) -> OWSURLSessionEndpoint)?

    public func buildUrlEndpoint(for signalServiceInfo: SignalServiceInfo) -> OWSURLSessionEndpoint {
        return urlEndpointBuilder?(signalServiceInfo) ?? OWSURLSessionEndpoint(
            baseUrl: signalServiceInfo.baseUrl,
            frontingInfo: nil,
            securityPolicy: .systemDefault(),
            extraHeaders: [:]
        )
    }

    public var mockUrlSessionBuilder: ((SignalServiceInfo, OWSURLSessionEndpoint, URLSessionConfiguration?) -> BaseOWSURLSessionMock)?

    public func buildUrlSession(
        for signalServiceInfo: SignalServiceInfo,
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration?
    ) -> OWSURLSessionProtocol {
        return mockUrlSessionBuilder?(signalServiceInfo, endpoint, configuration) ?? BaseOWSURLSessionMock(
            endpoint: endpoint,
            configuration: .default,
            maxResponseSize: nil
        )
    }
}

#endif
