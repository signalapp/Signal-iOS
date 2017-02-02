//  Created by Michael Kirk on 10/26/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import XCTest
import PromiseKit

struct VerificationFailedError : Error { }
struct FailedToGetRPRegistrationTokenError : Error { }
struct FailedToRegisterWithRedphoneError : Error { }

enum PushNotificationRequestResult : String {
    case FailTSOnly = "FailTSOnly",
    FailRPOnly = "FailRPOnly",
    FailBoth = "FailBoth",
    Succeed = "Succeed"
}

class FailingTSAccountManager : TSAccountManager {
    let phoneNumberAwaitingVerification = "+13235555555"

    override func verifyAccount(withCode: String, isWebRTCEnabled: Bool, success: @escaping () -> Void, failure: @escaping (Error) -> Void) -> Void {
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

class VerifyingTSAccountManager : FailingTSAccountManager {
    override func verifyAccount(withCode: String, isWebRTCEnabled: Bool, success: @escaping () -> Void, failure: @escaping (Error) -> Void) -> Void {
        success()
    }

    override func obtainRPRegistrationToken(success: @escaping (String) -> Void, failure failureBlock: @escaping (Error) -> Void) {
        failureBlock(FailedToGetRPRegistrationTokenError())
    }
}

class TokenObtainingTSAccountManager : VerifyingTSAccountManager {
    override func obtainRPRegistrationToken(success: @escaping (String) -> Void, failure failureBlock: @escaping (Error) -> Void) {
        success("fakeRegistrationToken")
    }
}

class FailingRPAccountManager : RPAccountManager {
    override func register(withTsToken tsToken: String, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        failure(FailedToRegisterWithRedphoneError());
    }
}

class SuccessfulRPAccountManager : RPAccountManager {
    override func register(withTsToken tsToken: String, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        if tsToken == "fakeRegistrationToken" {
            success()
        } else {
            XCTFail("Unexpected registration token:\(tsToken)")
        }
    }

    override func registerForPushNotifications(pushToken: String, voipToken: String, success successHandler: @escaping () -> Void, failure failureHandler: @escaping (Error) -> Void) {
        if pushToken == PushNotificationRequestResult.FailRPOnly.rawValue || pushToken == PushNotificationRequestResult.FailBoth.rawValue {
            failureHandler(OWSErrorMakeUnableToProcessServerResponseError())
        } else {
            successHandler()
        }
    }
}

class AccountManagerTest: XCTestCase {

    let tsAccountManager = FailingTSAccountManager()
    let rpAccountManager = FailingRPAccountManager()

    func testRegisterWhenEmptyCode() {
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager,
                                            redPhoneAccountManager: rpAccountManager)

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
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager,
                                            redPhoneAccountManager: rpAccountManager)

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

    func testObtainingTokenFails() {
        let tsAccountManager = VerifyingTSAccountManager()
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager,
                                            redPhoneAccountManager: rpAccountManager)

        let expectation = self.expectation(description: "should fail")

        firstly {
            accountManager.register(verificationCode: "123456")
        }.then {
            XCTFail("Should fail")
        }.catch { error in
            if error is FailedToGetRPRegistrationTokenError {
                expectation.fulfill()
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testRedPhoneRegistrationFails() {
        let tsAccountManager = TokenObtainingTSAccountManager()
        let rpAccountManager = FailingRPAccountManager()
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager,
                                            redPhoneAccountManager: rpAccountManager)

        let expectation = self.expectation(description: "should fail")

        firstly {
            accountManager.register(verificationCode: "123456")
        }.then {
            XCTFail("Should fail")
        }.catch { error in
            if error is FailedToRegisterWithRedphoneError {
                expectation.fulfill()
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testSuccessfulRegistration() {
        let tsAccountManager = TokenObtainingTSAccountManager()
        let rpAccountManager = SuccessfulRPAccountManager()
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager,
                                            redPhoneAccountManager: rpAccountManager)

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
        let accountManager = AccountManager(textSecureAccountManager: tsAccountManager,
                                            redPhoneAccountManager: rpAccountManager)


        let expectation = self.expectation(description: "should fail")

        accountManager.updatePushTokens(pushToken: PushNotificationRequestResult.FailTSOnly.rawValue, voipToken: "whatever").then {
            XCTFail("Expected to fail.")
        }.catch { error in
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }

}
