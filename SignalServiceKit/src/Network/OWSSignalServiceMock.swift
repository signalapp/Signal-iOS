//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class OWSSignalServiceMock: NSObject, OWSSignalServiceProtocol {

    public override init() {
        super.init()
    }

    public func warmCaches() {}

    public var keyValueStore = SDSKeyValueStore(collection: "")

    public var isCensorshipCircumventionActive: Bool = false

    public var hasCensoredPhoneNumber: Bool = false

    public var isCensorshipCircumventionManuallyActivated: Bool = false

    public var isCensorshipCircumventionManuallyDisabled: Bool = false

    public var manualCensorshipCircumventionCountryCode: String?

    public var urlEndpointBuilder: ((SignalServiceInfo) -> OWSURLSessionEndpoint)?

    public func typeUnsafe_buildUrlEndpoint(for signalServiceInfo: Any) -> Any {
        let signalServiceInfo = signalServiceInfo as! SignalServiceInfo
        return urlEndpointBuilder?(signalServiceInfo) ?? OWSURLSessionEndpoint(
            baseUrl: signalServiceInfo.baseUrl,
            frontingInfo: nil,
            securityPolicy: .systemDefault(),
            extraHeaders: [:]
        )
    }

    public var mockUrlSessionBuilder: ((SignalServiceInfo, OWSURLSessionEndpoint, URLSessionConfiguration?) -> OWSURLSessionMock)?

    public func typeUnsafe_buildUrlSession(for signalServiceInfo: Any, endpoint: OWSURLSessionEndpoint, configuration: URLSessionConfiguration?) -> Any {
        let signalServiceInfo = signalServiceInfo as! SignalServiceInfo
        return mockUrlSessionBuilder?(signalServiceInfo, endpoint, configuration) ?? OWSURLSessionMock(
            endpoint: endpoint,
            configuration: .default,
            maxResponseSize: nil
        )
    }
}
