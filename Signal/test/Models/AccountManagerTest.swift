//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
import PromiseKit
import SignalServiceKit
@testable import Signal

struct VerificationFailedError: Error { }
struct FailedToGetRPRegistrationTokenError: Error { }

enum PushNotificationRequestResult: String {
    case FailTSOnly = "FailTSOnly",
    FailRPOnly = "FailRPOnly",
    FailBoth = "FailBoth",
    Succeed = "Succeed"
}

class FailingTSAccountManager: TSAccountManager {
    override public init() {
        AssertIsOnMainThread()

        super.init()

        self.phoneNumberAwaitingVerification = "+13235555555"
    }

    override func verifyAccount(with request: TSRequest, success successBlock: @escaping (Any?) -> Void, failure failureBlock: @escaping (Error) -> Void) {
        failureBlock(VerificationFailedError())
    }

    override func registerForPushNotifications(pushToken: String, voipToken: String, success successHandler: @escaping () -> Void, failure failureHandler: @escaping (Error) -> Void) {
        if pushToken == PushNotificationRequestResult.FailTSOnly.rawValue || pushToken == PushNotificationRequestResult.FailBoth.rawValue {
            failureHandler(OWSErrorMakeUnableToProcessServerResponseError())
        } else {
            successHandler()
        }
    }
}

class VerifyingTSAccountManager: FailingTSAccountManager {
    override func verifyAccount(with request: TSRequest, success successBlock: @escaping (Any?) -> Void, failure failureBlock: @escaping (Error) -> Void) {
        successBlock(["uuid": UUID().uuidString])
    }

}

class TokenObtainingTSAccountManager: VerifyingTSAccountManager {
}

class VerifyingPushRegistrationManager: PushRegistrationManager {
    public override func requestPushTokens() -> Promise<(pushToken: String, voipToken: String)> {
        return Promise.value(("a", "b"))
    }
}

class AccountManagerTest: SignalBaseTest {

    override func setUp() {
        super.setUp()

        let tsAccountManager = FailingTSAccountManager()
        let sskEnvironment = SSKEnvironment.shared as! MockSSKEnvironment
        sskEnvironment.tsAccountManager = tsAccountManager
    }

    override func tearDown() {
        super.tearDown()
    }

    func testRegisterWhenEmptyCode() {
        let accountManager = AccountManager()

        let expectation = self.expectation(description: "should fail")

        firstly {
            accountManager.register(verificationCode: "", pin: "", checkForAvailableTransfer: false)
        }.done {
            XCTFail("Should fail")
        }.catch { error in
            let nserror = error as NSError
            if OWSErrorCode(rawValue: nserror.code) == OWSErrorCode.userError {
                expectation.fulfill()
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testRegisterWhenVerificationFails() {
        let accountManager = AccountManager()

        let expectation = self.expectation(description: "should fail")

        firstly {
            accountManager.register(verificationCode: "123456", pin: "", checkForAvailableTransfer: false)
        }.done {
            XCTFail("Should fail")
        }.catch { error in
            if error is VerificationFailedError {
                expectation.fulfill()
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testSuccessfulRegistration() {
        let tsAccountManager = TokenObtainingTSAccountManager()
        let sskEnvironment = SSKEnvironment.shared as! MockSSKEnvironment
        sskEnvironment.tsAccountManager = tsAccountManager

        AppEnvironment.shared.pushRegistrationManager = VerifyingPushRegistrationManager()

        let accountManager = AccountManager()

        let expectation = self.expectation(description: "should succeed")

        firstly {
            accountManager.register(verificationCode: "123456", pin: "", checkForAvailableTransfer: false)
        }.done {
            expectation.fulfill()
        }.catch { error in
            XCTFail("Unexpected error: \(error)")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testUpdatePushTokens() {
        let accountManager = AccountManager()

        let expectation = self.expectation(description: "should fail")

        firstly {
            accountManager.updatePushTokens(pushToken: PushNotificationRequestResult.FailTSOnly.rawValue, voipToken: "whatever")
        }.done {
            XCTFail("Expected to fail.")
        }.catch { _ in
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }
}
