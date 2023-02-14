//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class RegistrationSessionManagerMock: RegistrationSessionManager {

    public init() {}

    public var sessionToRestore: RegistrationSession?

    public func restoreSession() -> Guarantee<RegistrationSession?> {
        return .value(sessionToRestore)
    }

    public var beginSessionResponse: Guarantee<Registration.BeginSessionResponse>?
    public var didBeginOrRestoreSession = false

    public func beginOrRestoreSession(e164: String, apnsToken: String?) -> Guarantee<Registration.BeginSessionResponse> {
        didBeginOrRestoreSession = true
        return beginSessionResponse!
    }

    public var fulfillChallengeResponse: Guarantee<Registration.UpdateSessionResponse>?
    public var didFulfillChallenge = false

    public func fulfillChallenge(
        for session: RegistrationSession,
        fulfillment: Registration.ChallengeFulfillment
    ) -> Guarantee<Registration.UpdateSessionResponse> {
        didFulfillChallenge = true
        return fulfillChallengeResponse!
    }

    public var requestCodeResponse: Guarantee<Registration.UpdateSessionResponse>?
    public var didRequestCode = false

    public func requestVerificationCode(
        for session: RegistrationSession,
        transport: Registration.CodeTransport
    ) -> Guarantee<Registration.UpdateSessionResponse> {
        didRequestCode = true
        return requestCodeResponse!
    }

    public var submitCodeResponse: Guarantee<Registration.UpdateSessionResponse>?
    public var didSubmitCode = false

    public func submitVerificationCode(
        for session: RegistrationSession,
        code: String
    ) -> Guarantee<Registration.UpdateSessionResponse> {
        didSubmitCode = true
        return submitCodeResponse!
    }

    public func completeSession() {
        sessionToRestore = nil
    }
}
#endif
