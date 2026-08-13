//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct TSRequestRedactionTest {
    private func buildRequest(url: String) -> TSRequest {
        var request = TSRequest(url: URL(string: url)!, method: "GET", parameters: nil)
        request.auth = .anonymous
        return request
    }

    @Test
    func urlIsNotRedactedByDefault() {
        let request = buildRequest(url: "v1/subscription/subscriberId")

        #expect(request.debugDescription == "UD GET v1/subscription/subscriberId")
    }

    @Test
    func redactsSensitiveValuesInPath() {
        var request = buildRequest(url: "v1/subscription/subscriberId/level/500/USD/idempotencyKey")
        request.applyRedactionStrategy(.redactURL(sensitiveValues: [
            "subscriberId",
            "idempotencyKey",
        ]))

        #expect(request.debugDescription == "UD GET v1/subscription/[REDACTED]/level/500/USD/[REDACTED]")
    }

    @Test
    func redactsSensitiveValuesInQuery() {
        var request = buildRequest(url: "v1/devicecheck/assert?keyId=keyIdValue&request=requestValue")
        request.applyRedactionStrategy(.redactURL(sensitiveValues: [
            "keyIdValue",
            "requestValue",
        ]))

        #expect(request.debugDescription == "UD GET v1/devicecheck/assert?keyId=[REDACTED]&request=[REDACTED]")
    }

    @Test
    func redactsEveryOccurrenceOfASensitiveValue() {
        var request = buildRequest(url: "v1/subscription/subscriberId/appstore/subscriberId")
        request.applyRedactionStrategy(.redactURL(sensitiveValues: ["subscriberId"]))

        #expect(request.debugDescription == "UD GET v1/subscription/[REDACTED]/appstore/[REDACTED]")
    }

    @Test
    func retainsHeaderNames() {
        var request = buildRequest(url: "v1/subscription/subscriberId")
        request.headers["donation-permit"] = "permit"
        request.applyRedactionStrategy(.redactURL(sensitiveValues: ["subscriberId"]))

        #expect(request.debugDescription == "UD GET v1/subscription/[REDACTED] [donation-permit]")
    }

    // MARK: - Requests carrying sensitive values

    @Test
    func redactsSubscriberID() {
        let request = OWSRequestFactory.setSubscriberID(Data([255, 128]), donationPermit: nil)

        #expect(request.url.relativeString == "v1/subscription/_4A")
        #expect(request.debugDescription == "UD PUT v1/subscription/[REDACTED]")
    }

    @Test
    func redactsRegistrationSessionId() {
        let request = RegistrationRequestFactory.fetchSessionRequest(
            sessionId: "sessionId",
            logger: .empty(),
        )

        #expect(request.url.relativeString == "v1/verification/session/sessionId")
        #expect(request.debugDescription == "ID GET v1/verification/session/[REDACTED]")
    }
}
