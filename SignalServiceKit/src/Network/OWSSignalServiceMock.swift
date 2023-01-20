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
