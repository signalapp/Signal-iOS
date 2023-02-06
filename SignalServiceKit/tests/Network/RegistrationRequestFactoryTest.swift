//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

public class RegistrationRequestFactoryTest: XCTestCase {

    func test_requestVerificationCodeLocale() {
        // (languageCode, countryCode, expected header)
        let expectedValues: [(String?, String?, String)] = [
            ("en", "US", "en-US, en;q=0.9"),
            ("en", nil, "en"),
            ("es", "US", "es-US, es;q=0.9, en;q=0.8"),
            ("es", nil, "es, en;q=0.9"),
            (nil, nil, "en")
        ]

        for (languageCode, countryCode, expectedHeader) in expectedValues {
            let request = RegistrationRequestFactory.requestVerificationCodeRequest(
                sessionId: "123",
                languageCode: languageCode,
                countryCode: countryCode,
                transport: .sms
            )
            XCTAssertEqual(request.url?.relativeString, "v1/verification/session/123/code")
            XCTAssertEqual(request.parameters["transport"] as? String, "sms")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), expectedHeader)
        }
    }
}
