//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import XCTest
import PromiseKit

struct VerificationFailedError: Error { }
struct FailedToGetRPRegistrationTokenError: Error { }

enum PushNotificationRequestResult: String {
    case FailTSOnly = "FailTSOnly",
    FailRPOnly = "FailRPOnly",
    FailBoth = "FailBoth",
    Succeed = "Succeed"
}

class FailingTSAccountManager: TSAccountManager {
    let phoneNumberAwaitingVerification = "+13235555555"

    override func verifyAccount(withCode: String, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        failure(VerificationFailedError())
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
    override func verifyAccount(withCode: String, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        success()
    }
}

class TokenObtainingTSAccountManager: VerifyingTSAccountManager {
}

class AccountManagerTest: XCTestCase {

    let tsAccountManager = FailingTSAccountManager()

    func testRegisterWhenEmptyCode() {
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager)

        let expectation = self.expectation(description: "should fail")

        firstly {
            accountManager.register(verificationCode: "")
        }.then {
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
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager)

        let expectation = self.expectation(description: "should fail")

        firstly {
            accountManager.register(verificationCode: "123456")
        }.then {
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
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager)

        let expectation = self.expectation(description: "should succeed")

        firstly {
            accountManager.register(verificationCode: "123456")
        }.then {
            expectation.fulfill()
        }.catch { error in
            XCTFail("Unexpected error: \(error)")
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testUpdatePushTokens() {
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager)

        let expectation = self.expectation(description: "should fail")

        accountManager.updatePushTokens(pushToken: PushNotificationRequestResult.FailTSOnly.rawValue, voipToken: "whatever").then {
            XCTFail("Expected to fail.")
        }.catch { _ in
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

}
