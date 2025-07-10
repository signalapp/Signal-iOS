//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class RegistrationSessionManagerMock: RegistrationSessionManager {

    public init() {}

    // MARK: - RestoreSession

    public var sessionToRestore: RegistrationSession?

    public func restoreSession() -> RegistrationSession? {
        return sessionToRestore
    }

    public func clearPersistedSession(_ transaction: DBWriteTransaction) {
        sessionToRestore = nil
    }

    // MARK: - BeginOrRestoreSession

    private var beginSessionResponseMocks = [Registration.BeginSessionResponse]()
    public func addBeginSessionResponseMock(_ mock: Registration.BeginSessionResponse) {
        beginSessionResponseMocks.append(mock)
    }

    public func beginOrRestoreSession(e164: E164, apnsToken: String?) async -> Registration.BeginSessionResponse {
        // TODO: Append step to known steps
        return beginSessionResponseMocks.removeFirst()
    }

    // MARK: - FulfillChallenge

    private var fulfillChallengeResponseMocks = [Registration.UpdateSessionResponse]()
    public var latestChallengeFulfillment: Registration.ChallengeFulfillment?
    public func addFulfillChallengeResponseMock(_ mock: Registration.UpdateSessionResponse) {
        fulfillChallengeResponseMocks.append(mock)
    }
    public func fulfillChallenge(
        for session: RegistrationSession,
        fulfillment: Registration.ChallengeFulfillment
    ) async -> Registration.UpdateSessionResponse {
        latestChallengeFulfillment = fulfillment
        return fulfillChallengeResponseMocks.removeFirst()
    }

    // MARK: - RequestVerificationCode

    public var didRequestCode = false
    private var requestCodeResponseMocks = [Registration.UpdateSessionResponse]()
    public func addRequestCodeResponseMock(_ mock: Registration.UpdateSessionResponse) {
        requestCodeResponseMocks.append(mock)
    }
    public func requestVerificationCode(
        for session: RegistrationSession,
        transport: Registration.CodeTransport
    ) async -> Registration.UpdateSessionResponse {
        didRequestCode = true
        // TODO: Append step to known steps
        return requestCodeResponseMocks.removeFirst()
    }

    // MARK: - SubmitVerificationCod

    private var submitCodeResponseMocks = [Registration.UpdateSessionResponse]()
    public func addSubmitCodeResponseMock(_ mock: Registration.UpdateSessionResponse) {
        submitCodeResponseMocks.append(mock)
    }

    public func submitVerificationCode(
        for session: RegistrationSession,
        code: String
    ) async -> Registration.UpdateSessionResponse {
        return submitCodeResponseMocks.removeFirst()
    }
}
#endif
