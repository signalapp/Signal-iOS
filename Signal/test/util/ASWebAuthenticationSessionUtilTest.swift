//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import AuthenticationServices
@testable import Signal

final class ASWebAuthenticationSessionUtilTest: XCTestCase {
    func testSuccess() {
        let inputUrl = URL(string: "https://example.com")!

        switch ASWebAuthenticationSession.resultify(callbackUrl: inputUrl, error: nil) {
        case let .success(url):
            XCTAssertEqual(url, inputUrl)
        default:
            XCTFail("Didn't get a successful result")
        }
    }

    func testFailure() {
        enum TestError: Error { case test }
        let inputError = TestError.test

        switch ASWebAuthenticationSession.resultify(callbackUrl: nil, error: inputError) {
        case let .failure(error):
            XCTAssertEqual(error as? TestError, inputError)
        default:
            XCTFail("Didn't get a failure result")
        }
    }
}
