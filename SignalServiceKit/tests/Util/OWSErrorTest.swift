//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

final class OWSErrorTest: XCTestCase {

    func testErrorProperties1() {
        enum FooError: Error {
            case bar
        }

        let errorFooBar = FooError.bar
        let errorGeneric = OWSGenericError("Yipes!")
        let error1 = OWSHTTPError.invalidRequest
        let error2 = OWSHTTPError.networkFailure(.genericFailure)
        let error3 = OWSUnretryableError()
        let error4 = OWSRetryableError()
        let error5 = MessageSenderNoSuchSignalRecipientError()

        XCTAssertFalse(errorFooBar.hasIsRetryable)
        XCTAssertTrue(errorFooBar.isRetryable)
        XCTAssertFalse(errorFooBar.isFatalError)

        XCTAssertTrue(errorGeneric.hasIsRetryable)
        XCTAssertFalse(errorGeneric.isRetryable)
        XCTAssertFalse(errorGeneric.isFatalError)

        XCTAssertTrue(error1.hasIsRetryable)
        XCTAssertFalse(error1.isRetryable)
        XCTAssertFalse(error1.isFatalError)

        XCTAssertTrue(error2.hasIsRetryable)
        XCTAssertTrue(error2.isRetryable)
        XCTAssertFalse(error2.isFatalError)

        XCTAssertTrue(error3.hasIsRetryable)
        XCTAssertFalse(error3.isRetryable)
        XCTAssertFalse(error3.isFatalError)

        XCTAssertTrue(error4.hasIsRetryable)
        XCTAssertTrue(error4.isRetryable)
        XCTAssertFalse(error4.isFatalError)

        XCTAssertTrue(error5.hasIsRetryable)
        XCTAssertFalse(error5.isRetryable)
        XCTAssertFalse(error5.isFatalError)
    }

    func testOWSError1() {
        let errorCode1: Int = 999
        let errorDescription1: String = "abc"
        let isRetryable1: Bool = true
        let error1: Error = OWSError(errorCode: errorCode1, description: errorDescription1, isRetryable: isRetryable1)

        XCTAssertEqual((error1 as NSError).code, errorCode1)
        XCTAssertEqual((error1 as NSError).domain, OWSError.errorDomain)
        XCTAssertTrue(error1.hasUserErrorDescription)
        XCTAssertEqual(error1.userErrorDescription, errorDescription1)
        XCTAssertTrue(error1.hasIsRetryable)
        XCTAssertEqual(error1.isRetryable, isRetryable1)

        let nsError1: NSError = error1 as NSError
        XCTAssertEqual(nsError1.code, errorCode1)
        XCTAssertEqual(nsError1.domain, OWSError.errorDomain)
        XCTAssertTrue(nsError1.hasUserErrorDescription)
        XCTAssertEqual(nsError1.userErrorDescription, errorDescription1)
        XCTAssertTrue(nsError1.hasIsRetryable)
        XCTAssertEqual(nsError1.isRetryable, isRetryable1)

        do {
            try ErrorThrower(error: error1).performThrow()
            XCTFail("Thrower did not throw.")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode1)
            XCTAssertEqual((error as NSError).domain, OWSError.errorDomain)
            XCTAssertTrue(error.hasUserErrorDescription)
            XCTAssertEqual(error.userErrorDescription, errorDescription1)
            XCTAssertTrue(error.hasIsRetryable)
            XCTAssertEqual(error.isRetryable, isRetryable1)
        }

        do {
            try ErrorThrower(error: nsError1).performThrow()
            XCTFail("Thrower did not throw.")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode1)
            XCTAssertEqual((error as NSError).domain, OWSError.errorDomain)
            XCTAssertTrue(error.hasUserErrorDescription)
            XCTAssertEqual(error.userErrorDescription, errorDescription1)
            XCTAssertTrue(error.hasIsRetryable)
            XCTAssertEqual(error.isRetryable, isRetryable1)
        }
    }

    func testOWSError2() {
        let errorCode1: Int = 1001
        let errorDescription1: String = "Some copy."
        let isRetryable1: Bool = false
        let error1: Error = OWSError(errorCode: errorCode1, description: errorDescription1, isRetryable: isRetryable1)

        XCTAssertEqual((error1 as NSError).code, errorCode1)
        XCTAssertEqual((error1 as NSError).domain, OWSError.errorDomain)
        XCTAssertTrue(error1.hasUserErrorDescription)
        XCTAssertEqual(error1.userErrorDescription, errorDescription1)
        XCTAssertTrue(error1.hasIsRetryable)
        XCTAssertEqual(error1.isRetryable, isRetryable1)

        let nsError1: NSError = error1 as NSError
        XCTAssertEqual(nsError1.code, errorCode1)
        XCTAssertEqual(nsError1.domain, OWSError.errorDomain)
        XCTAssertTrue(nsError1.hasUserErrorDescription)
        XCTAssertEqual(nsError1.userErrorDescription, errorDescription1)
        XCTAssertTrue(nsError1.hasIsRetryable)
        XCTAssertEqual(nsError1.isRetryable, isRetryable1)

        do {
            try ErrorThrower(error: error1).performThrow()
            XCTFail("Thrower did not throw.")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode1)
            XCTAssertEqual((error as NSError).domain, OWSError.errorDomain)
            XCTAssertTrue(error.hasUserErrorDescription)
            XCTAssertEqual(error.userErrorDescription, errorDescription1)
            XCTAssertTrue(error.hasIsRetryable)
            XCTAssertEqual(error.isRetryable, isRetryable1)
        }

        do {
            try ErrorThrower(error: nsError1).performThrow()
            XCTFail("Thrower did not throw.")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode1)
            XCTAssertEqual((error as NSError).domain, OWSError.errorDomain)
            XCTAssertTrue(error.hasUserErrorDescription)
            XCTAssertEqual(error.userErrorDescription, errorDescription1)
            XCTAssertTrue(error.hasIsRetryable)
            XCTAssertEqual(error.isRetryable, isRetryable1)
        }
    }

    func testOWSError3() {
        let errorCode1: Int = 999
        let errorDescription1: String = "abc"
        let isRetryable1: Bool = false
        let error1: Error = OWSError(errorCode: errorCode1,
                                     description: errorDescription1,
                                     isRetryable: isRetryable1)

        XCTAssertEqual((error1 as NSError).code, errorCode1)
        XCTAssertEqual((error1 as NSError).domain, OWSError.errorDomain)
        XCTAssertTrue(error1.hasUserErrorDescription)
        XCTAssertEqual(error1.userErrorDescription, errorDescription1)
        XCTAssertTrue(error1.hasIsRetryable)
        XCTAssertEqual(error1.isRetryable, isRetryable1)

        let nsError1: NSError = error1 as NSError
        XCTAssertEqual(nsError1.code, errorCode1)
        XCTAssertEqual(nsError1.domain, OWSError.errorDomain)
        XCTAssertTrue(nsError1.hasUserErrorDescription)
        XCTAssertEqual(nsError1.userErrorDescription, errorDescription1)
        XCTAssertTrue(nsError1.hasIsRetryable)
        XCTAssertEqual(nsError1.isRetryable, isRetryable1)

        do {
            try ErrorThrower(error: error1).performThrow()
            XCTFail("Thrower did not throw.")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode1)
            XCTAssertEqual((error as NSError).domain, OWSError.errorDomain)
            XCTAssertTrue(error.hasUserErrorDescription)
            XCTAssertEqual(error.userErrorDescription, errorDescription1)
            XCTAssertTrue(error.hasIsRetryable)
            XCTAssertEqual(error.isRetryable, isRetryable1)
        }

        do {
            try ErrorThrower(error: nsError1).performThrow()
            XCTFail("Thrower did not throw.")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode1)
            XCTAssertEqual((error as NSError).domain, OWSError.errorDomain)
            XCTAssertTrue(error.hasUserErrorDescription)
            XCTAssertEqual(error.userErrorDescription, errorDescription1)
            XCTAssertTrue(error.hasIsRetryable)
            XCTAssertEqual(error.isRetryable, isRetryable1)
        }
    }

    func testOWSError4() {
        let errorCode1: Int = 999
        let errorDescription1: String = "abc"
        let nsError1: NSError = NSError(domain: OWSError.errorDomain,
                                        code: errorCode1,
                                        userInfo: [
                                            NSLocalizedDescriptionKey: errorDescription1
                                        ])
        let error1: Error = nsError1 as Error

        XCTAssertEqual((error1 as NSError).code, errorCode1)
        XCTAssertEqual((error1 as NSError).domain, OWSError.errorDomain)
        XCTAssertFalse(error1.hasUserErrorDescription)
        XCTAssertFalse(error1.hasIsRetryable)

        XCTAssertEqual(nsError1.code, errorCode1)
        XCTAssertEqual(nsError1.domain, OWSError.errorDomain)
        XCTAssertFalse(nsError1.hasUserErrorDescription)
        XCTAssertFalse(nsError1.hasIsRetryable)

        do {
            try ErrorThrower(error: error1).performThrow()
            XCTFail("Thrower did not throw.")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode1)
            XCTAssertEqual((error as NSError).domain, OWSError.errorDomain)
            XCTAssertFalse(error.hasUserErrorDescription)
            XCTAssertFalse(error.hasIsRetryable)
        }

        do {
            try ErrorThrower(error: nsError1).performThrow()
            XCTFail("Thrower did not throw.")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode1)
            XCTAssertEqual((error as NSError).domain, OWSError.errorDomain)
            XCTAssertFalse(error.hasUserErrorDescription)
            XCTAssertFalse(error.hasIsRetryable)
        }
    }

    // MARK: -

    struct ErrorThrower {
        let error: Error

        func performThrow() throws {
            throw error
        }
    }
}
