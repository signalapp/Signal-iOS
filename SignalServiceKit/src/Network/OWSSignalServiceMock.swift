//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

    public var domainFrontBaseURL: URL = OWSCensorshipConfiguration.default().domainFrontBaseURL

    public func buildCensorshipConfiguration() -> OWSCensorshipConfiguration {
        return .default()
    }

    public var mockUrlSessionBuilder: ((SignalServiceType) -> OWSURLSessionMock)?

    public func typeUnsafe_buildUrlSession(for signalServiceType: Any) -> Any {
        let signalServiceType = signalServiceType as! SignalServiceType
        return mockUrlSessionBuilder?(signalServiceType) ?? OWSURLSessionMock(
            baseUrl: signalServiceType.signalServiceInfo().baseUrl,
            frontingInfo: nil,
            securityPolicy: .systemDefault(),
            configuration: .default,
            extraHeaders: [:], maxResponseSize: nil
        )
    }
}
