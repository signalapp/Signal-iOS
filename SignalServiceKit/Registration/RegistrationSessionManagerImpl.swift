//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CoreTelephony

final public class RegistrationSessionManagerImpl: RegistrationSessionManager {

    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let signalService: OWSSignalServiceProtocol

    public init(
        dateProvider: @escaping DateProvider = Date.provider,
        db: any DB,
        signalService: OWSSignalServiceProtocol
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: KvStore.collectionName)
        self.signalService = signalService
    }

    // TODO: make this and other methods resilient to transient network failures by adding
    // basic retrying logic.
    public func restoreSession() async -> RegistrationSession? {
        // Just get the most recent one, don't validate against any e164.
        return await restoreSession(forE164: nil)
    }

    public func beginOrRestoreSession(e164: E164, apnsToken: String?) async -> Registration.BeginSessionResponse {
        // Verify the session is still valid.
        let restoredSession = await restoreSession(forE164: e164)
        guard let restoredSession, restoredSession.e164 == e164 else {
            // We only keep one session at a time, wipe any if we change the e164.
            await db.awaitableWrite { self.clearPersistedSession($0) }

            let (mcc, mnc) = Self.getMccMnc()

            let response = await makeBeginSessionRequest(
                e164: e164,
                apnsToken: apnsToken,
                mcc: mcc,
                mnc: mnc
            )
            return await persistSessionFromResponse(response)
        }
        return .success(restoredSession)
    }

    public func fulfillChallenge(
        for session: RegistrationSession,
        fulfillment: Registration.ChallengeFulfillment
    ) async -> Registration.UpdateSessionResponse {
        let response = await makeFulfillChallengeRequest(session, fulfillment)
        return await persistSessionFromResponse(response)
    }

    public func requestVerificationCode(for session: RegistrationSession, transport: Registration.CodeTransport) async -> Registration.UpdateSessionResponse {
        let response = await makeRequestVerificationCodeRequest(session, transport)
        return await persistSessionFromResponse(response)
    }

    public func submitVerificationCode(for session: RegistrationSession, code: String) async -> Registration.UpdateSessionResponse {
        let response = await makeSubmitVerificationCodeRequest(session, code: code)
        return await persistSessionFromResponse(response)
    }

    public func clearPersistedSession(_ transaction: DBWriteTransaction) {
        kvStore.removeValue(forKey: KvStore.sessionKey, transaction: transaction)
    }

    // MARK: - Session persistence

    internal enum KvStore {
        static let collectionName = "RegistrationSession"
        static let sessionKey = "session"
    }

    private func persist(session: RegistrationSession, _ transaction: DBWriteTransaction) {
        do {
            try kvStore.setCodable(session, key: KvStore.sessionKey, transaction: transaction)
        } catch {
            owsFailDebug("Unable to encode session; will not be recoverable after app relaunch.")
        }
    }

    private func getPersistedSession(_ transaction: DBReadTransaction) -> RegistrationSession? {
        do {
            return try kvStore.getCodableValue(forKey: KvStore.sessionKey, transaction: transaction)
        } catch {
            owsFailDebug("Unable to decode session; will not be recoverable after app relaunch.")
            return nil
        }
    }

    private func persistSessionFromResponse(_ response: Registration.BeginSessionResponse) async -> Registration.BeginSessionResponse {
        switch response {
        case .success(let session):
            await db.awaitableWrite { self.persist(session: session, $0) }
        case .invalidArgument, .retryAfter, .networkFailure, .genericError:
            break
        }
        return response
    }

    private func persistSessionFromResponse(_ response: Registration.UpdateSessionResponse) async -> Registration.UpdateSessionResponse {
        switch response {
        case
            let .success(session),
            let .disallowed(session),
            let .rejectedArgument(session),
            let .retryAfterTimeout(session),
            let .transportError(session):
            await db.awaitableWrite { self.persist(session: session, $0) }
        case .invalidSession:
            // Clear the session we've stored as it's invalid.
            await db.awaitableWrite { self.clearPersistedSession($0) }
        case .serverFailure, .networkFailure, .genericError:
            break
        }
        return response
    }

    private func persistSessionFromResponse(_ response: FetchSessionResponse) async -> FetchSessionResponse {
        switch response {
        case .success(let session):
            await db.awaitableWrite { self.persist(session: session, $0) }
        case .sessionInvalid:
            await db.awaitableWrite { self.clearPersistedSession($0) }
        case .genericError:
            break
        }
        return response
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

    // TODO: make this and other methods resilient to transient network failures by adding
    // basic retrying logic.
    private func restoreSession(forE164 e164: E164?) async -> RegistrationSession? {
        guard let existingSession = db.read(block: { self.getPersistedSession($0) }) else {
            return nil
        }
        if let e164, existingSession.e164 != e164 {
            // We only keep one session at a time, wipe any if we change the e164.
            await db.awaitableWrite { self.clearPersistedSession($0) }
            return nil
        }
        // Verify the session is still valid.
        let fetchSessionResponse = await makeFetchSessionRequest(existingSession)
        _ = await self.persistSessionFromResponse(fetchSessionResponse)
        switch fetchSessionResponse {
        case .success(let session):
            return session
        case .sessionInvalid, .genericError:
            return nil
        }
    }

    // MARK: Begin Session

    private func makeBeginSessionRequest(
        e164: E164,
        apnsToken: String?,
        mcc: String?,
        mnc: String?
    ) async -> Registration.BeginSessionResponse {
        let request = RegistrationRequestFactory.beginSessionRequest(
            e164: e164,
            pushToken: apnsToken,
            mcc: mcc,
            mnc: mnc
        )
        return await makeRequest(
            request,
            e164: e164,
            handler: self.handleBeginSessionResponse(forE164:statusCode:retryAfterHeader:bodyData:),
            fallbackError: .genericError,
            networkFailureError: .networkFailure
        )
    }

    private func handleBeginSessionResponse(
        forE164 e164: E164,
        statusCode: Int,
        retryAfterHeader: String?,
        bodyData: Data?
    ) -> Registration.BeginSessionResponse {
        let statusCode = RegistrationServiceResponses.BeginSessionResponseCodes(rawValue: statusCode)
        switch statusCode {
        case .success:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .success($0) } ?? .genericError
        case .invalidArgument, .missingArgument:
            return .invalidArgument
        case .retry:
            let retryAfter: TimeInterval
            if
                let retryAfterHeader,
                let retryAfterTime = TimeInterval(retryAfterHeader)
            {
                retryAfter = retryAfterTime
            } else {
                retryAfter = Constants.defaultRetryTime
            }
            return .retryAfter(retryAfter)
        case .unexpectedError, .none:
            return .genericError
        }
    }

    // MARK: Fulfill Challenge

    private func makeFulfillChallengeRequest(
        _ session: RegistrationSession,
        _ fulfillment: Registration.ChallengeFulfillment
    ) async -> Registration.UpdateSessionResponse {
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
            pushChallengeToken: pushChallengeToken
        )
        return await makeUpdateRequest(
            request,
            session: session,
            handler: self.handleFulfillChallengeResponse(sessionAtSendTime:statusCode:bodyData:)
        )
    }

    private func handleFulfillChallengeResponse(
        sessionAtSendTime: RegistrationSession,
        statusCode: Int,
        bodyData: Data?
    ) -> Registration.UpdateSessionResponse {
        let e164 = sessionAtSendTime.e164
        let statusCode = RegistrationServiceResponses.FulfillChallengeResponseCodes(rawValue: statusCode)
        switch statusCode {
        case .success:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .success($0) } ?? .genericError
        case .notAccepted:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .rejectedArgument($0) } ?? .genericError
        case .missingSession:
            return .invalidSession
        case .malformedRequest:
            Logger.error("Malformed fulfill challenge request")
            return .genericError
        case .unexpectedError, .none:
            return .genericError
        }
    }

    // MARK: Request Verification Code

    private func makeRequestVerificationCodeRequest(
        _ session: RegistrationSession,
        _ transport: Registration.CodeTransport
    ) async -> Registration.UpdateSessionResponse {
        let wireTransport: RegistrationRequestFactory.VerificationCodeTransport
        switch transport {
        case .sms:
            wireTransport = .sms
        case .voice:
            wireTransport = .voice
        }

        // In an abstract sense we should mock these out for testing, but
        // for any concrete test we'd want to write the language code doesn't matter
        // at all. Its serialization is already tested at a lower level.
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
            transport: wireTransport
        )
        return await makeUpdateRequest(
            request,
            session: session,
            handler: self.handleRequestVerificationCodeResponse(sessionAtSendTime:statusCode:bodyData:)
        )
    }

    private func handleRequestVerificationCodeResponse(
        sessionAtSendTime: RegistrationSession,
        statusCode: Int,
        bodyData: Data?
    ) -> Registration.UpdateSessionResponse {
        let e164 = sessionAtSendTime.e164
        let statusCode = RegistrationServiceResponses.RequestVerificationCodeResponseCodes(rawValue: statusCode)
        switch statusCode {
        case .success:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .success($0) } ?? .genericError
        case .disallowed:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .disallowed($0) } ?? .genericError
        case .retry:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .retryAfterTimeout($0) } ?? .genericError
        case .providerFailure:
            return serverFailureResponse(fromResponseBody: bodyData, sessionAtSendTime: sessionAtSendTime).map { .serverFailure($0) } ?? .genericError
        case .missingSession:
            return .invalidSession
        case .transportError:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .transportError($0) } ?? .genericError
        case .malformedRequest, .unexpectedError, .none:
            return .genericError
        }
    }

    // MARK: Submit Verification Code

    private func makeSubmitVerificationCodeRequest(
        _ session: RegistrationSession,
        code: String
    ) async -> Registration.UpdateSessionResponse {
        let request = RegistrationRequestFactory.submitVerificationCodeRequest(
            sessionId: session.id,
            code: code
        )
        return await makeUpdateRequest(
            request,
            session: session,
            handler: self.handleSubmitVerificationCodeResponse(sessionAtSendTime:statusCode:bodyData:)
        )
    }

    private func handleSubmitVerificationCodeResponse(
        sessionAtSendTime: RegistrationSession,
        statusCode: Int,
        bodyData: Data?
    ) -> Registration.UpdateSessionResponse {
        let e164 = sessionAtSendTime.e164
        let statusCode = RegistrationServiceResponses.SubmitVerificationCodeResponseCodes(rawValue: statusCode)
        switch statusCode {
        case .success:
            guard let session = registrationSession(
                    fromResponseBody: bodyData,
                    e164: e164
                )
            else {
                return .genericError
            }
            if session.verified {
                return .success(session)
            } else {
                return .rejectedArgument(session)
            }
        case .malformedRequest:
            Logger.error("Verification code was invalidly formatted (not just incorrect).")
            return .genericError
        case .retry:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .retryAfterTimeout($0) } ?? .genericError
        case .missingSession:
            return .invalidSession
        case .newCodeRequired:
            guard let session = registrationSession(
                    fromResponseBody: bodyData,
                    e164: e164
                )
            else {
                return .genericError
            }
            if session.verified {
                // Unclear how this could happen but hey,
                // the session is verified. Pretend that worked
                // and keep going
                return .success(session)
            } else if session.nextVerificationAttempt != nil {
                // We can submit a code, but not yet.
                return .retryAfterTimeout(session)
            } else {
                // There is no code to submit.
                return .disallowed(session)
            }
        case .unexpectedError, .none:
            return .genericError
        }
    }

    // MARK: Fetch Session

    private enum FetchSessionResponse: Equatable {
        case success(RegistrationSession)
        /// This session is known to be invalid or timed out.
        /// It should be thrown away and another session started.
        case sessionInvalid
        /// Some other error occurred; an error might be shown to the user
        /// but the session shouldn't be discarded.
        case genericError
    }

    private func makeFetchSessionRequest(
        _ session: RegistrationSession
    ) async -> FetchSessionResponse {
        let request = RegistrationRequestFactory.fetchSessionRequest(sessionId: session.id)
        do {
            let response = try await signalService.urlSessionForMainSignalService().performRequest(request)
            return handleFetchSessionResponse(
                sessionAtSendTime: session,
                statusCode: response.responseStatusCode,
                bodyData: response.responseBodyData
            )
        } catch {
            guard let error = error as? OWSHTTPError else {
                return .genericError
            }
            let response = handleFetchSessionResponse(
                sessionAtSendTime: session,
                statusCode: error.responseStatusCode,
                bodyData: error.httpResponseData
            )
            return response
        }
    }

    private func handleFetchSessionResponse(
        sessionAtSendTime: RegistrationSession,
        statusCode: Int,
        bodyData: Data?
    ) -> FetchSessionResponse {
        let e164 = sessionAtSendTime.e164
        let statusCode = RegistrationServiceResponses.FetchSessionResponseCodes(rawValue: statusCode)
        switch statusCode {
        case .success:
            return registrationSession(
                fromResponseBody: bodyData,
                e164: e164
            ).map { .success($0) } ?? .genericError
        case .missingSession:
            return .sessionInvalid
        case .unexpectedError, .none:
            return .genericError
        }
    }

    // MARK: - Generic Request Helpers

    enum Constants {
        static let defaultRetryTime: TimeInterval = 3

        static let retryAfterHeader = "retry-after"
    }

    private func registrationSession(
        fromResponseBody bodyData: Data?,
        e164: E164
    ) -> RegistrationSession? {
        guard let bodyData else {
            Logger.warn("Got empty registration session response")
            return nil
        }
        guard let session = try? JSONDecoder().decode(RegistrationServiceResponses.RegistrationSession.self, from: bodyData) else {
            Logger.warn("Unable to parse registration session from response")
            return nil
        }
        return session.toLocalSession(forE164: e164, receivedAt: dateProvider())
    }

    private func serverFailureResponse(
        fromResponseBody bodyData: Data?,
        sessionAtSendTime: RegistrationSession
    ) -> Registration.ServerFailureResponse? {
        guard let bodyData else {
            Logger.warn("Got empty provider failure response")
            return nil
        }
        guard let failure = try? JSONDecoder().decode(RegistrationServiceResponses.SendVerificationCodeFailedResponse.self, from: bodyData) else {
            Logger.warn("Unable to parse registration session from response")
            return nil
        }
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
            session: sessionAtSendTime,
            isPermanent: failure.permanentFailure,
            reason: localReason
        )
    }

    private func makeRequest<ResponseType>(
        _ request: TSRequest,
        e164: E164,
        handler: @escaping (_ e164: E164, _ statusCode: Int, _ retryAfterHeader: String?, _ bodyData: Data?) -> ResponseType,
        fallbackError: ResponseType,
        networkFailureError: ResponseType
    ) async -> ResponseType {
        do {
            let response = try await signalService.urlSessionForMainSignalService().performRequest(request)
            return handler(
                e164,
                response.responseStatusCode,
                response.headers[Constants.retryAfterHeader],
                response.responseBodyData
            )
        } catch {
            if error.isNetworkFailureOrTimeout {
                return networkFailureError
            }
            guard let error = error as? OWSHTTPError else {
                return fallbackError
            }
            return handler(
                e164,
                error.responseStatusCode,
                error.responseHeaders?.value(forHeader: Constants.retryAfterHeader),
                error.httpResponseData
            )
        }
    }

    private func makeUpdateRequest(
        _ request: TSRequest,
        session: RegistrationSession,
        handler: @escaping (_ priorSession: RegistrationSession, _ statusCode: Int, _ bodyData: Data?) -> Registration.UpdateSessionResponse
    ) async -> Registration.UpdateSessionResponse {
        return await makeRequest(
            request,
            e164: session.e164,
            handler: { _, statusCode, _, bodyData in
                return handler(session, statusCode, bodyData)
            },
            fallbackError: .genericError,
            networkFailureError: .networkFailure
        )
    }
}

fileprivate extension RegistrationServiceResponses.RegistrationSession {

    func toLocalSession(
        forE164 e164: E164,
        receivedAt: Date
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
            verified: verified
        )
    }
}

fileprivate extension RegistrationServiceResponses.RegistrationSession.Challenge {

    var asLocalChallenge: RegistrationSession.Challenge? {
        switch self {
        case .captcha: return .captcha
        case .pushChallenge: return .pushChallenge
        case .unknown: return nil
        }
    }
}
