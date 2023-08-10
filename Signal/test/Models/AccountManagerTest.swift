//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
@testable import SignalServiceKit

struct VerificationFailedError: Error { }
struct FailedToGetRPRegistrationTokenError: Error { }

enum PushNotificationRequestResult: String {
    case failTSOnly = "FailTSOnly"
    case failRPOnly = "FailRPOnly"
    case failBoth = "FailBoth"
    case succeed = "Succeed"
}

class FailingTSAccountManager: TSAccountManager {
    override public init() {
        AssertIsOnMainThread()

        super.init()

        self.phoneNumberAwaitingVerification = E164ObjC(E164("+13235555555")!)
    }

    override func verifyRegistration(request: TSRequest,
                                     success successBlock: @escaping (Any?) -> Void,
                                     failure failureBlock: @escaping (Error) -> Void) {
        failureBlock(VerificationFailedError())
    }

    override func registerForPushNotifications(pushToken: String,
                                               voipToken: String?,
                                               success successHandler: @escaping () -> Void,
                                               failure failureHandler: @escaping (Error) -> Void) {
        if pushToken == PushNotificationRequestResult.failTSOnly.rawValue || pushToken == PushNotificationRequestResult.failBoth.rawValue {
            failureHandler(OWSGenericError("Missing or invalid push token."))
        } else {
            successHandler()
        }
    }
}

class VerifyingTSAccountManager: FailingTSAccountManager {
    override func verifyRegistration(request: TSRequest,
                                     success successBlock: @escaping (Any?) -> Void,
                                     failure failureBlock: @escaping (Error) -> Void) {
        successBlock(["uuid": UUID().uuidString, "pni": UUID().uuidString])
    }
}

class TokenObtainingTSAccountManager: VerifyingTSAccountManager {
}

class VerifyingPushRegistrationManager: PushRegistrationManager {
    public override func requestPushTokens(forceRotation: Bool, timeOutEventually: Bool = false) -> Promise<PushRegistrationManager.ApnRegistrationId> {
        return .value(.init(apnsToken: "a", voipToken: "b"))
    }
}

class AccountManagerTest: SignalBaseTest {

    override func setUp() {
        super.setUp()

        let tsAccountManager = FailingTSAccountManager()
        SSKEnvironment.shared.setTsAccountManagerForUnitTests(tsAccountManager)
    }

    override func tearDown() {
        super.tearDown()
    }

    func testUpdatePushTokens() {
        let accountManager = AccountManager()

        let expectation = self.expectation(description: "should fail")

        firstly {
            accountManager.updatePushTokens(pushToken: PushNotificationRequestResult.failTSOnly.rawValue, voipToken: "whatever")
        }.done {
            XCTFail("Expected to fail.")
        }.catch { _ in
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: 1.0, handler: nil)
    }
}
