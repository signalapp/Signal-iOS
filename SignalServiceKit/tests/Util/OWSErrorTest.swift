//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class OWSErrorTest: SSKBaseTestSwift {

    func testErrorProperties1() {
        enum FooError: Error {
            case bar
        }

        let errorFooBar = FooError.bar
        let errorGeneric = OWSGenericError("Yipes!")
        let error1 = OWSHTTPError.invalidRequest(requestUrl: URL(string: "https://google.com/")!)
        let error2 = OWSHTTPError.networkFailure(requestUrl: URL(string: "https://google.com/")!)
        let error3 = OWSUnretryableError()
        let error4 = OWSRetryableError()

        XCTAssertFalse(errorFooBar.hasIsRetryable)
        XCTAssertTrue(errorFooBar.isRetryable)
        XCTAssertFalse(errorFooBar.shouldBeIgnoredForGroups)
        XCTAssertFalse(errorFooBar.isFatalError)

        XCTAssertTrue(errorGeneric.hasIsRetryable)
        XCTAssertFalse(errorGeneric.isRetryable)
        XCTAssertFalse(errorGeneric.shouldBeIgnoredForGroups)
        XCTAssertFalse(errorGeneric.isFatalError)

        XCTAssertTrue(error1.hasIsRetryable)
        XCTAssertFalse(error1.isRetryable)
        XCTAssertFalse(error1.shouldBeIgnoredForGroups)
        XCTAssertFalse(error1.isFatalError)

        XCTAssertTrue(error2.hasIsRetryable)
        XCTAssertTrue(error2.isRetryable)
        XCTAssertFalse(error2.shouldBeIgnoredForGroups)
        XCTAssertFalse(error2.isFatalError)

        XCTAssertTrue(error3.hasIsRetryable)
        XCTAssertFalse(error3.isRetryable)
        XCTAssertFalse(error3.shouldBeIgnoredForGroups)
        XCTAssertFalse(error3.isFatalError)

        XCTAssertTrue(error4.hasIsRetryable)
        XCTAssertTrue(error4.isRetryable)
        XCTAssertFalse(error4.shouldBeIgnoredForGroups)
        XCTAssertFalse(error4.isFatalError)
    }
}

// MARK: -

extension Error {
    var debugPointerName: String {
        String(describing: Unmanaged<AnyObject>.passUnretained(self as AnyObject).toOpaque())
    }
}
