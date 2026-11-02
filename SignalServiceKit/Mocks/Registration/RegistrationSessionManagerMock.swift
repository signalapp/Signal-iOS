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

    public func restoreSession(logger: PrefixedLogger) -> RegistrationSession? {
        return sessionToRestore
    }

    public func clearPersistedSession(_ transaction: DBWriteTransaction) {
        sessionToRestore = nil
    }

    // MARK: - BeginOrRestoreSession

    private var beginSessionResponseMocks = [() async throws -> RegistrationSession]()
    public func addBeginSessionResponseMock(_ mock: @escaping () async throws -> RegistrationSession) {
        beginSessionResponseMocks.append(mock)
    }

    public func beginOrRestoreSession(e164: E164, apnsToken: String?, logger: PrefixedLogger) async throws -> RegistrationSession {
        // TODO: Append step to known steps
        return try await beginSessionResponseMocks.removeFirst()()
    }

    // MARK: - FulfillChallenge

    private var fulfillChallengeResponseMocks = [(inout RegistrationSession, Registration.ChallengeFulfillment) async throws -> Void]()
    public func addFulfillChallengeResponseMock(_ mock: @escaping (inout RegistrationSession, Registration.ChallengeFulfillment) async throws -> Void) {
        fulfillChallengeResponseMocks.append(mock)
    }

    public func fulfillChallenge(
        for session: inout RegistrationSession,
        fulfillment: Registration.ChallengeFulfillment,
        logger: PrefixedLogger,
    ) async throws {
        try await fulfillChallengeResponseMocks.removeFirst()(&session, fulfillment)
    }

    // MARK: - RequestVerificationCode

    private var requestVerificationCodeMocks = [(inout RegistrationSession) async throws -> Void]()
    public func addRequestVerificationCodeMock(_ mock: @escaping (inout RegistrationSession) async throws -> Void) {
        requestVerificationCodeMocks.append(mock)
    }

    public func requestVerificationCode(
        for session: inout RegistrationSession,
        transport: Registration.CodeTransport,
        logger: PrefixedLogger,
    ) async throws {
        // TODO: Append step to known steps
        return try await requestVerificationCodeMocks.removeFirst()(&session)
    }

    // MARK: - SubmitVerificationCod

    private var submitVerificationCodeMocks = [(inout RegistrationSession) async throws -> Void]()
    public func addSubmitVerificationCodeMock(_ mock: @escaping (inout RegistrationSession) async throws -> Void) {
        submitVerificationCodeMocks.append(mock)
    }

    public func submitVerificationCode(
        for session: inout RegistrationSession,
        code: String,
        logger: PrefixedLogger,
    ) async throws {
        try await submitVerificationCodeMocks.removeFirst()(&session)
    }
}
#endif
