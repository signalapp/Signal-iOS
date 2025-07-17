//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension RegistrationCoordinatorImpl {

    enum Service {

        enum SVR2AuthCheckResponse {
            case success(RegistrationServiceResponses.SVR2AuthCheckResponse)
            case networkError
            case genericError
        }

        static func makeSVR2AuthCheckRequest(
            e164: E164,
            candidateCredentials: [SVR2AuthCredential],
            signalService: OWSSignalServiceProtocol,
        ) async -> SVR2AuthCheckResponse {
            let request = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
                e164: e164,
                credentials: candidateCredentials
            )
            return await makeRequest(
                request,
                signalService: signalService,
                handler: self.handleSVR2AuthCheckResponse(statusCode:retryAfterHeader:bodyData:),
                fallbackError: .genericError,
                networkFailureError: .networkError
            )
        }

        private static func handleSVR2AuthCheckResponse(
            statusCode: Int,
            retryAfterHeader: String?,
            bodyData: Data?
        ) -> SVR2AuthCheckResponse {
            let statusCode = RegistrationServiceResponses.SVR2AuthCheckResponseCodes(rawValue: statusCode)
            switch statusCode {
            case .success:
                guard let bodyData else {
                    Logger.warn("Got empty KBS auth check response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(RegistrationServiceResponses.SVR2AuthCheckResponse.self, from: bodyData) else {
                    Logger.warn("Unable to parse KBS auth check response from response")
                    return .genericError
                }

                return .success(response)
            case .malformedRequest, .invalidJSON:
                Logger.error("Malformed kbs auth check request")
                return .genericError
            case .none, .unexpectedError:
                return .genericError
            }
        }

        static func makeCreateAccountRequest(
            _ method: RegistrationRequestFactory.VerificationMethod,
            e164: E164,
            authPassword: String,
            accountAttributes: AccountAttributes,
            skipDeviceTransfer: Bool,
            apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
            prekeyBundles: RegistrationPreKeyUploadBundles,
            signalService: OWSSignalServiceProtocol,
        ) async -> AccountResponse {
            let request = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: method,
                e164: e164,
                authPassword: authPassword,
                accountAttributes: accountAttributes,
                skipDeviceTransfer: skipDeviceTransfer,
                apnRegistrationId: apnRegistrationId,
                prekeyBundles: prekeyBundles
            )
            return await makeRequest(
                request,
                signalService: signalService,
                handler: {
                    self.handleCreateAccountResponse(
                        authPassword: authPassword,
                        statusCode: $0,
                        retryAfterHeader: $1,
                        bodyData: $2
                    )
                },
                fallbackError: .genericError,
                networkFailureError: .networkError
            )
        }

        private static func handleCreateAccountResponse(
            authPassword: String,
            statusCode: Int,
            retryAfterHeader: String?,
            bodyData: Data?
        ) -> AccountResponse {
            let statusCode = RegistrationServiceResponses.AccountCreationResponseCodes(rawValue: statusCode)
            switch statusCode {
            case .success:
                guard let bodyData else {
                    Logger.warn("Got empty create account response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(RegistrationServiceResponses.AccountIdentityResponse.self, from: bodyData) else {
                    Logger.warn("Unable to parse Account identity from response")
                    return .genericError
                }
                return .success(AccountIdentity(
                    aci: response.aci,
                    pni: response.pni,
                    e164: response.e164,
                    hasPreviouslyUsedSVR: response.hasPreviouslyUsedSVR,
                    authPassword: authPassword
                ))

            case .deviceTransferPossible:
                return .deviceTransferPossible

            case .regRecoveryPasswordRejected:
                Logger.warn("Reg recovery password rejected when creating account.")
                return .rejectedVerificationMethod

            case .reglockFailed:
                guard let bodyData else {
                    Logger.warn("Got empty create account response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(
                    RegistrationServiceResponses.RegistrationLockFailureResponse.self,
                    from: bodyData
                ) else {
                    Logger.warn("Unable to parse ReglockFailure from response")
                    return .genericError
                }
                return .reglockFailure(response)

            case .retry:
                let retryAfter: TimeInterval
                if
                    let retryAfterHeader,
                    let retryAfterTime = TimeInterval(retryAfterHeader)
                {
                    retryAfter = retryAfterTime
                } else {
                    Logger.warn("Missing retry-after header from server; falling back to default.")
                    retryAfter = Constants.defaultRetryTime
                }
                return .retryAfter(retryAfter)

            case .unauthorized:
                Logger.warn("Got unauthorized response for create account")
                return .rejectedVerificationMethod

            case .invalidArgument:
                Logger.warn("Got invalid argument response for create account")
                return .genericError

            case .malformedRequest:
                Logger.warn("Got malformed request response for create account")
                return .genericError

            case .none, .unexpectedError:
                return .genericError
            }
        }

        static func makeChangeNumberRequest(
            _ method: RegistrationRequestFactory.VerificationMethod,
            e164: E164,
            reglockToken: String?,
            authPassword: String,
            pniChangeNumberParameters: PniDistribution.Parameters,
            signalService: OWSSignalServiceProtocol,
        ) async -> AccountResponse {
            let request = RegistrationRequestFactory.changeNumberRequest(
                verificationMethod: method,
                e164: e164,
                reglockToken: reglockToken,
                pniChangeNumberParameters: pniChangeNumberParameters
            )
            return await makeRequest(
                request,
                signalService: signalService,
                handler: {
                    return self.handleChangeNumberResponse(authPassword: authPassword, statusCode: $0, retryAfterHeader: $1, bodyData: $2)
                },
                fallbackError: .genericError,
                networkFailureError: .networkError
            )
        }

        private static func handleChangeNumberResponse(
            authPassword: String,
            statusCode: Int,
            retryAfterHeader: String?,
            bodyData: Data?
        ) -> AccountResponse {
            let statusCode = RegistrationServiceResponses.ChangeNumberResponseCodes(rawValue: statusCode)
            switch statusCode {
            case .success:
                guard let bodyData else {
                    Logger.warn("Got empty create account response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(RegistrationServiceResponses.AccountIdentityResponse.self, from: bodyData) else {
                    Logger.warn("Unable to parse Account identity from response")
                    return .genericError
                }
                return .success(AccountIdentity(
                    aci: response.aci,
                    pni: response.pni,
                    e164: response.e164,
                    hasPreviouslyUsedSVR: response.hasPreviouslyUsedSVR,
                    authPassword: authPassword
                ))

            case .reglockFailed:
                guard let bodyData else {
                    Logger.warn("Got empty create account response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(
                    RegistrationServiceResponses.RegistrationLockFailureResponse.self,
                    from: bodyData
                ) else {
                    Logger.warn("Unable to parse ReglockFailure from response")
                    return .genericError
                }
                return .reglockFailure(response)

            case .retry:
                let retryAfter: TimeInterval
                if
                    let retryAfterHeader,
                    let retryAfterTime = TimeInterval(retryAfterHeader)
                {
                    retryAfter = retryAfterTime
                } else {
                    Logger.warn("Missing retry-after header from server; falling back to default.")
                    retryAfter = Constants.defaultRetryTime
                }
                return .retryAfter(retryAfter)

            case .unauthorized, .regRecoveryPasswordRejected:
                return .rejectedVerificationMethod

            case .malformedRequest:
                Logger.error("Got malformed request for change number")
                return .genericError

            case .invalidArgument:
                Logger.error("Got invalid argument for change number")
                return .genericError

            case .mismatchedDevicesToNotify, .mismatchedDevicesToNotifyRegistrationIds:
                // TODO[PNP]: What should be done about this category of error?
                Logger.error("Got mismatched device list information for change number")
                return .genericError

            case .none, .unexpectedError:
                return .genericError
            }
        }

        public static func makeEnableReglockRequest(
            reglockToken: String,
            auth: ChatServiceAuth,
            signalService: OWSSignalServiceProtocol,
            retriesLeft: Int = RegistrationCoordinatorImpl.Constants.networkErrorRetries
        ) async throws {
            var request = OWSRequestFactory.enableRegistrationLockV2Request(token: reglockToken)
            request.auth = .identified(auth)
            do {
                _ = try await signalService.urlSessionForMainSignalService().performRequest(request)
            } catch {
                if error.isNetworkFailureOrTimeout, retriesLeft > 0 {
                    return try await makeEnableReglockRequest(
                        reglockToken: reglockToken,
                        auth: auth,
                        signalService: signalService,
                        retriesLeft: retriesLeft - 1
                    )
                }
                throw error
            }
        }

        public static func makeUpdateAccountAttributesRequest(
            _ attributes: AccountAttributes,
            auth: ChatServiceAuth,
            signalService: OWSSignalServiceProtocol,
            retriesLeft: Int = RegistrationCoordinatorImpl.Constants.networkErrorRetries
        ) async throws {
            let request = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                attributes,
                auth: auth
            )
            do {
                let response = try await signalService.urlSessionForMainSignalService().performRequest(request)
                guard response.responseStatusCode >= 200, response.responseStatusCode < 300 else {
                    // Errors are undifferentiated; the only actual error we can get is an unauthenticated
                    // one and there isn't any way to handle that as different from a, say server 500.
                    throw OWSAssertionError("Got unexpected response code from update attributes request: \(response.responseStatusCode).")
                }
            } catch {
                if error.isNetworkFailureOrTimeout, retriesLeft > 0 {
                    return try await makeUpdateAccountAttributesRequest(
                        attributes,
                        auth: auth,
                        signalService: signalService,
                        retriesLeft: retriesLeft - 1
                    )
                }
                throw error
            }
        }

        enum WhoAmIResponse {
            case success(WhoAmIRequestFactory.Responses.WhoAmI)
            case networkError
            case genericError
        }

        public static func makeWhoAmIRequest(
            auth: ChatServiceAuth,
            signalService: OWSSignalServiceProtocol,
            retriesLeft: Int = RegistrationCoordinatorImpl.Constants.networkErrorRetries
        ) async -> WhoAmIResponse {
            let request = WhoAmIRequestFactory.whoAmIRequest(auth: auth)
            do {
                let response = try await signalService.urlSessionForMainSignalService().performRequest(request)
                guard response.responseStatusCode >= 200, response.responseStatusCode < 300 else {
                    return .genericError
                }
                guard let bodyData = response.responseBodyData else {
                    Logger.error("Got empty whoami response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(WhoAmIRequestFactory.Responses.WhoAmI.self, from: bodyData) else {
                    Logger.error("Unable to parse whoami response from response")
                    return .genericError
                }
                return .success(response)
            } catch {
                if error.isNetworkFailureOrTimeout, retriesLeft > 0 {
                    return await makeWhoAmIRequest(
                        auth: auth,
                        signalService: signalService,
                        retriesLeft: retriesLeft - 1,
                    )
                }
                return error.isNetworkFailureOrTimeout ? .networkError : .genericError
            }
        }

        private static func makeRequest<ResponseType>(
            _ request: TSRequest,
            signalService: OWSSignalServiceProtocol,
            handler: (_ statusCode: Int, _ retryAfterHeader: String?, _ bodyData: Data?) -> ResponseType,
            fallbackError: ResponseType,
            networkFailureError: ResponseType
        ) async -> ResponseType {
            do {
                let response = try await signalService.urlSessionForMainSignalService().performRequest(request)
                return handler(
                    response.responseStatusCode,
                    response.headers[Constants.retryAfterHeader],
                    response.responseBodyData
                )
            } catch where error.isNetworkFailureOrTimeout {
                return networkFailureError
            } catch let error as OWSHTTPError {
                return handler(
                    error.responseStatusCode,
                    error.responseHeaders?[Constants.retryAfterHeader],
                    error.httpResponseData
                )
            } catch {
                return fallbackError
            }
        }

        enum Constants {
            static let defaultRetryTime: TimeInterval = 3

            static let retryAfterHeader = "retry-after"
        }
    }
}
