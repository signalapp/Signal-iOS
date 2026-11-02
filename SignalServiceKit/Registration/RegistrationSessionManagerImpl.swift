//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreTelephony
import Foundation

public class RegistrationSessionManagerImpl: RegistrationSessionManager {

    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: NewKeyValueStore
    private let networkManager: any NetworkManagerProtocol

    public init(
        dateProvider: @escaping DateProvider = Date.provider,
        db: any DB,
        networkManager: any NetworkManagerProtocol,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = NewKeyValueStore(collection: KvStore.collectionName)
        self.networkManager = networkManager
    }

    public func restoreSession(logger: PrefixedLogger) async -> RegistrationSession? {
        // Just get the most recent one, don't validate against any e164.
        return await restoreSession(forE164: nil, logger: logger)
    }

    public func beginOrRestoreSession(e164: E164, apnsToken: String?, logger: PrefixedLogger) async throws -> RegistrationSession {
        let restoredSession = await restoreSession(forE164: e164, logger: logger)
        if let restoredSession {
            return restoredSession
        }

        let (mcc, mnc) = Self.getMccMnc()

        let session = try await makeBeginSessionRequest(
            e164: e164,
            apnsToken: apnsToken,
            mcc: mcc,
            mnc: mnc,
            logger: logger,
        )
        await db.awaitableWrite { tx in self.persist(session: session, tx) }
        return session
    }

    public func fulfillChallenge(
        for session: inout RegistrationSession,
        fulfillment: Registration.ChallengeFulfillment,
        logger: PrefixedLogger,
    ) async throws {
        try await updatingSession(&session) { session, updatedSession in
            try await makeFulfillChallengeRequest(
                forSession: session,
                updatedSession: &updatedSession,
                fulfillment: fulfillment,
                logger: logger,
            )
        }
    }

    public func requestVerificationCode(
        for session: inout RegistrationSession,
        transport: Registration.CodeTransport,
        logger: PrefixedLogger,
    ) async throws {
        try await updatingSession(&session) { session, updatedSession in
            try await makeRequestVerificationCodeRequest(
                forSession: session,
                updatedSession: &updatedSession,
                transport: transport,
                logger: logger,
            )
        }
    }

    public func submitVerificationCode(
        for session: inout RegistrationSession,
        code: String,
        logger: PrefixedLogger,
    ) async throws {
        try await updatingSession(&session) { session, updatedSession in
            try await makeSubmitVerificationCodeRequest(
                forSession: session,
                updatedSession: &updatedSession,
                code: code,
                logger: logger,
            )
        }
    }

    public func clearPersistedSession(_ transaction: DBWriteTransaction) {
        kvStore.removeValue(forKey: KvStore.sessionKey, tx: transaction)
    }

    // MARK: - Session persistence

    enum KvStore {
        static let collectionName = "RegistrationSession"
        static let sessionKey = "session"
    }

    private func persist(session: RegistrationSession, _ transaction: DBWriteTransaction) {
        kvStore.writeValueAsJSON(session, forKey: KvStore.sessionKey, tx: transaction)
    }

    private func getPersistedSession(_ transaction: DBReadTransaction) -> RegistrationSession? {
        do {
            return try kvStore.fetchJSONAsValue(RegistrationSession.self, forKey: KvStore.sessionKey, tx: transaction)
        } catch {
            owsFailDebug("Unable to decode session; will not be recoverable after app relaunch.")
            return nil
        }
    }

    private func updatingSession(
        _ session: inout RegistrationSession,
        block: (_ session: RegistrationSession, _ updatedSession: inout RegistrationSession?) async throws -> Void,
    ) async throws {
        var updatedSession: RegistrationSession?
        let result = await Result(catching: { try await block(session, &updatedSession) })
        if let updatedSession {
            session = updatedSession
            await db.awaitableWrite { tx in self.persist(session: session, tx) }
        }
        try result.get()
    }

    // MARK: - MCC/MNC

    private static func getMccMnc() -> (mcc: String?, mnc: String?) {
        guard
            let providers = CTTelephonyNetworkInfo().serviceSubscriberCellularProviders,
            let provider = providers.values.first
        else {
            Logger.info("Unable to get telephony info for mcc/mnc.")
            return (nil, nil)
        }
        if providers.values.count > 1 {
            Logger.info("Multiple telephony providers found; using the first for mcc/mnc.")
        }
        return (provider.mobileCountryCode, provider.mobileNetworkCode)
    }

    // MARK: - Requests

    private func restoreSession(forE164 e164: E164?, logger: PrefixedLogger) async -> RegistrationSession? {
        guard var existingSession = db.read(block: { self.getPersistedSession($0) }) else {
            return nil
        }
        if let e164, existingSession.e164 != e164 {
            // We only keep one session at a time, wipe any if we change the e164.
            await db.awaitableWrite { self.clearPersistedSession($0) }
            return nil
        }
        // Verify the session is still valid.
        do {
            try await Retry.performWithBackoff(maxAttempts: 2, isRetryable: { $0.isNetworkFailureOrTimeout }) {
                try await updatingSession(&existingSession) { existingSession, updatedSession in
                    try await makeFetchSessionRequest(forSession: existingSession, updatedSession: &updatedSession, logger: logger)
                }
            }
            return existingSession
        } catch is Registration.MissingSessionError {
            // The session isn't valid, so wipe it and create a new one.
            await db.awaitableWrite { self.clearPersistedSession($0) }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: Begin Session

    private func makeBeginSessionRequest(
        e164: E164,
        apnsToken: String?,
        mcc: String?,
        mnc: String?,
        logger: PrefixedLogger,
    ) async throws -> RegistrationSession {
        let request = RegistrationRequestFactory.beginSessionRequest(
            e164: e164,
            pushToken: apnsToken,
            mcc: mcc,
            mnc: mnc,
            logger: logger,
        )
        let response = try await networkManager.asyncRequest(request)
        return try registrationSession(fromResponseBody: response.responseBodyData, e164: e164)
    }

    // MARK: Fulfill Challenge

    private func makeFulfillChallengeRequest(
        forSession session: RegistrationSession,
        updatedSession: inout RegistrationSession?,
        fulfillment: Registration.ChallengeFulfillment,
        logger: PrefixedLogger,
    ) async throws {
        let captchaToken: String?
        let pushChallengeToken: String?
        switch fulfillment {
        case .captcha(let token):
            captchaToken = token
            pushChallengeToken = nil
        case .pushChallenge(let token):
            captchaToken = nil
            pushChallengeToken = token
        }
        let request = RegistrationRequestFactory.fulfillChallengeRequest(
            sessionId: session.id,
            captchaToken: captchaToken,
            pushChallengeToken: pushChallengeToken,
            logger: logger,
        )
        do {
            let response = try await networkManager.asyncRequest(request)
            updatedSession = try registrationSession(fromResponseBody: response.responseBodyData, e164: session.e164)
        } catch where error.httpStatusCode == Registration.challengeRejectedErrorCode {
            // the challenge token provided did not match
            updatedSession = try registrationSession(fromResponseBody: error.httpResponseData, e164: session.e164)
            throw error
        } catch where error.httpStatusCode == 404 {
            throw Registration.MissingSessionError()
        }
    }

    // MARK: Request Verification Code

    private func makeRequestVerificationCodeRequest(
        forSession session: RegistrationSession,
        updatedSession: inout RegistrationSession?,
        transport: Registration.CodeTransport,
        logger: PrefixedLogger,
    ) async throws {
        let wireTransport: RegistrationRequestFactory.VerificationCodeTransport
        switch transport {
        case .sms:
            wireTransport = .sms
        case .voice:
            wireTransport = .voice
        }

        let locale = Locale.current
        let languageCode: String?
        let countryCode: String?
        if #available(iOS 16, *) {
            languageCode = locale.language.languageCode?.identifier
            countryCode = locale.region?.identifier
        } else {
            languageCode = locale.languageCode
            countryCode = locale.regionCode
        }

        let request = RegistrationRequestFactory.requestVerificationCodeRequest(
            sessionId: session.id,
            languageCode: languageCode,
            countryCode: countryCode,
            transport: wireTransport,
            logger: logger,
        )
        do {
            let response = try await networkManager.asyncRequest(request)
            updatedSession = try registrationSession(fromResponseBody: response.responseBodyData, e164: session.e164)
        } catch where error.httpStatusCode == 404 {
            throw Registration.MissingSessionError()
        } catch where error.httpStatusCode == Registration.RequestVerificationCodeErrorCode.notYetAllowed.rawValue {
            /// The current session state disallows requesting a code. The client may
            /// have to fulfill some challenge before proceeding, or the session might
            /// already be verified. Check the session object to know.
            updatedSession = try registrationSession(fromResponseBody: error.httpResponseData, e164: session.e164)
            throw error
        } catch where error.httpStatusCode == Registration.RequestVerificationCodeErrorCode.notEverSupported.rawValue {
            /// The chosen transport mode is not supported (likely scoped to the e164),
            /// but another transport may be supported.
            updatedSession = try registrationSession(fromResponseBody: error.httpResponseData, e164: session.e164)
            throw error
        } catch where error.httpStatusCode == Registration.RequestVerificationCodeErrorCode.rateLimited.rawValue {
            /// May need to wait before trying again; check session object for timeouts.
            /// If no timeout is specified, a different transport or starting a fresh
            /// session may be required.
            updatedSession = try registrationSession(fromResponseBody: error.httpResponseData, e164: session.e164)
            throw error
        } catch where error.httpStatusCode == 440 {
            /// The attempt to send a verification code failed because an external
            /// service (e.g. the SMS provider) refused to deliver the code.
            let failureResponse = try serverFailureResponse(fromResponseBody: error.httpResponseData)
            throw Registration.RequestRejectedByProviderError(failureResponse: failureResponse)
        }
    }

    // MARK: Submit Verification Code

    private func makeSubmitVerificationCodeRequest(
        forSession session: RegistrationSession,
        updatedSession: inout RegistrationSession?,
        code: String,
        logger: PrefixedLogger,
    ) async throws {
        let request = RegistrationRequestFactory.submitVerificationCodeRequest(
            sessionId: session.id,
            code: code,
            logger: logger,
        )
        do {
            let response = try await networkManager.asyncRequest(request)
            let newSession = try registrationSession(fromResponseBody: response.responseBodyData, e164: session.e164)
            updatedSession = newSession
        } catch where error.httpStatusCode == 404 {
            throw Registration.MissingSessionError()
        } catch where error.httpStatusCode == Registration.SubmitVerificationCodeErrorCode.notAllowed.rawValue {
            // This session will not accept additional verification code submissions
            // either because no code has been sent for this session (clients must
            // request and presumably receive a verification code before submitting a
            // code) or because the phone number has already been verified with another
            // code.
            let newSession = try registrationSession(fromResponseBody: error.httpResponseData, e164: session.e164)
            updatedSession = newSession
            if newSession.verified {
                // Unclear how this could happen but hey, the session is verified. Pretend
                // that worked and keep going
                return
            }
            throw error
        } catch where error.httpStatusCode == Registration.SubmitVerificationCodeErrorCode.rateLimited.rawValue {
            // May need to wait before trying again; check session object for timeouts.
            // If no timeout is specified, sending a new code or starting a fresh
            // session may be required.
            updatedSession = try registrationSession(fromResponseBody: error.httpResponseData, e164: session.e164)
            throw error
        }
    }

    // MARK: Fetch Session

    private func makeFetchSessionRequest(
        forSession session: RegistrationSession,
        updatedSession: inout RegistrationSession?,
        logger: PrefixedLogger,
    ) async throws {
        let request = RegistrationRequestFactory.fetchSessionRequest(sessionId: session.id, logger: logger)
        do {
            let response = try await networkManager.asyncRequest(request)
            updatedSession = try registrationSession(fromResponseBody: response.responseBodyData, e164: session.e164)
        } catch where error.httpStatusCode == 404 {
            throw Registration.MissingSessionError()
        }
    }

    // MARK: - Generic Request Helpers

    private func registrationSession(
        fromResponseBody bodyData: Data?,
        e164: E164,
    ) throws -> RegistrationSession {
        let session = try JSONDecoder().decode(RegistrationServiceResponses.RegistrationSession.self, from: bodyData ?? Data())
        return session.toLocalSession(forE164: e164, receivedAt: dateProvider())
    }

    private func serverFailureResponse(fromResponseBody bodyData: Data?) throws -> Registration.ServerFailureResponse {
        let failure = try JSONDecoder().decode(
            RegistrationServiceResponses.SendVerificationCodeFailedResponse.self,
            from: bodyData ?? Data(),
        )
        let reasonString: String = {
            switch failure.reason {
            case .none, .unknown:
                return "unknown"
            case .providerRejected:
                return "provider rejected"
            case .providerUnavailable:
                return "provider unavailable"
            case .illegalArgument:
                return "illegal argument (rejected number)"
            }
        }()
        Logger.error("Sending verification code failure from service provider. Permanent:\(failure.permanentFailure) Reason:\(reasonString)")
        let localReason: Registration.ServerFailureResponse.Reason?
        switch failure.reason {
        case .unknown, .none:
            localReason = nil
        case .providerRejected:
            localReason = .providerRejected
        case .providerUnavailable:
            localReason = .providerUnavailable
        case .illegalArgument:
            localReason = .illegalArgument
        }
        return Registration.ServerFailureResponse(
            isPermanent: failure.permanentFailure,
            reason: localReason,
        )
    }
}

private extension RegistrationServiceResponses.RegistrationSession {

    func toLocalSession(
        forE164 e164: E164,
        receivedAt: Date,
    ) -> RegistrationSession {
        let mappedChallenges = requestedInformation.compactMap(\.asLocalChallenge)
        let hasUnknownChallengeRequiringAppUpdate = mappedChallenges.count != requestedInformation.count
        return RegistrationSession(
            id: id,
            e164: e164,
            receivedDate: receivedAt,
            nextSMS: nextSms.map { TimeInterval($0) },
            nextCall: nextCall.map { TimeInterval($0) },
            nextVerificationAttempt: nextVerificationAttempt.map { TimeInterval($0) },
            allowedToRequestCode: allowedToRequestCode,
            requestedInformation: mappedChallenges,
            hasUnknownChallengeRequiringAppUpdate: hasUnknownChallengeRequiringAppUpdate,
            verified: verified,
        )
    }
}

private extension RegistrationServiceResponses.RegistrationSession.Challenge {

    var asLocalChallenge: RegistrationSession.Challenge? {
        switch self {
        case .captcha: return .captcha
        case .pushChallenge: return .pushChallenge
        case .unknown: return nil
        }
    }
}
