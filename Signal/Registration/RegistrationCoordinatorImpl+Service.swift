//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension RegistrationCoordinatorImpl {

    enum Service {

        static func makeSVR2AuthCheckRequest(
            e164: E164,
            candidateCredentials: [SVR2AuthCredential],
            networkManager: any NetworkManagerProtocol,
            logger: PrefixedLogger,
        ) async throws -> RegistrationServiceResponses.SVR2AuthCheckResponse {
            let request = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
                e164: e164,
                credentials: candidateCredentials,
                logger: logger,
            )
            let response = try await networkManager.asyncRequest(request)
            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }
            return try JSONDecoder().decode(
                RegistrationServiceResponses.SVR2AuthCheckResponse.self,
                from: response.responseBodyData ?? Data(),
            )
        }

        static func makeCreateAccountRequest(
            _ requestContext: RegistrationRequestFactory.CreateAccountRequestContext,
            authPassword: String,
            accountAttributes: AccountAttributes,
            skipDeviceTransfer: Bool,
            apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
            aciPreKeyBundle: RegistrationPreKeyUploadBundle,
            networkManager: any NetworkManagerProtocol,
            logger: PrefixedLogger,
        ) async throws -> AccountIdentityResponse {
            let request = RegistrationRequestFactory.createAccountRequest(
                requestContext,
                authPassword: authPassword,
                accountAttributes: accountAttributes,
                skipDeviceTransfer: skipDeviceTransfer,
                apnRegistrationId: apnRegistrationId,
                aciPreKeyBundle: aciPreKeyBundle,
                logger: logger,
            )
            let response: HTTPResponse
            do {
                response = try await networkManager.asyncRequest(request)
            } catch where error.httpStatusCode == 401 && requestContext.hasSessionId {
                /// The Authorization header was invalid or the provided credentials were
                /// insufficient to verify ownership of the given phone number. Response
                /// body has an optional string error message.
                throw Registration.SessionRejectedError()
            } catch where error.httpStatusCode == 401 && requestContext.hasReceiptCredential {
                throw Registration.ReceiptCredentialRejectedError()
            } catch where error.httpStatusCode == 403 && requestContext.hasRecoveryPassword {
                /// The provided registration recovery password is either incorrect or
                /// registration via reg recovery password is impossible for this number.
                throw Registration.RecoveryPasswordRejectedError()
            } catch where error.httpStatusCode == 409 {
                /// The caller has not explicitly elected to skip transferring data from
                /// another device, but a device transfer is technically possible.
                throw Registration.DeviceTransferPossibleError()
            } catch where error.httpStatusCode == 423 {
                /// An account with the given phone number already exists and has a
                /// registration lock, and the client has not provided appropriate reglock
                /// credentials (either because the user input the wrong PIN (and thus
                /// couldn't retrieve any credential) or because the client used the wrong
                /// AEP/SvrKey to generate the credential). Response body has
                /// `RegistrationLockFailureResponse`.
                let parsedResponse = try JSONDecoder().decode(
                    RegistrationServiceResponses.RegistrationLockFailureResponse.self,
                    from: error.httpResponseData ?? Data(),
                )
                throw Registration.ReglockError(failureResponse: parsedResponse)
            }
            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }
            return try JSONDecoder().decode(
                AccountIdentityResponse.self,
                from: response.responseBodyData ?? Data(),
            )
        }

        static func makeChangeNumberRequest(
            _ requestContext: RegistrationRequestFactory.ChangeNumberRequestContext,
            newPhoneNumber: E164,
            reglockToken: RegistrationLock?,
            pniChangeNumberParameters: PniDistribution.Parameters,
            networkManager: any NetworkManagerProtocol,
            logger: PrefixedLogger,
        ) async throws -> AccountIdentityResponse {
            let request = RegistrationRequestFactory.changeNumberRequest(
                requestContext,
                newPhoneNumber: newPhoneNumber,
                reglockToken: reglockToken,
                pniChangeNumberParameters: pniChangeNumberParameters,
                logger: logger,
            )
            let response: HTTPResponse
            do {
                response = try await networkManager.asyncRequest(request)
            } catch where error.httpStatusCode == 401 && requestContext.hasSessionId {
                /// The provided credentials were insufficient to verify ownership of the
                /// given phone number.
                throw Registration.SessionRejectedError()
            } catch where error.httpStatusCode == 403 && requestContext.hasRecoveryPassword {
                /// The provided registration recovery password is either incorrect or
                /// registration via reg recovery password is impossible for this number.
                throw Registration.RecoveryPasswordRejectedError()
            } catch where error.httpStatusCode == 409 {
                /// The devices to notify in the request did not match the known linked
                /// devices.
                Logger.error("Got mismatched device list information for change number")
                // TODO[PNP]: What should be done about this category of error?
                throw error
            } catch where error.httpStatusCode == 410 {
                /// The devices to notify in the request were correct, but their provided
                /// registrationIds did not match.
                Logger.error("Got mismatched device list information for change number")
                // TODO[PNP]: What should be done about this category of error?
                throw error
            } catch where error.httpStatusCode == 423 {
                /// An account with the given phone number already exists and has a
                /// registration lock, and the client has not provided appropriate reglock
                /// credentials (either because the user input the wrong PIN (and thus
                /// couldn't retrieve any credential) or because the client used the wrong
                /// AEP/SvrKey to generate the credential). Response body has
                /// `RegistrationLockFailureResponse`.
                let parsedResponse = try JSONDecoder().decode(
                    RegistrationServiceResponses.RegistrationLockFailureResponse.self,
                    from: error.httpResponseData ?? Data(),
                )
                throw Registration.ReglockError(failureResponse: parsedResponse)
            }
            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }
            return try JSONDecoder().decode(
                AccountIdentityResponse.self,
                from: response.responseBodyData ?? Data(),
            )
        }

        static func makeWhoAmIRequest(
            auth: ChatServiceAuth,
            networkManager: any NetworkManagerProtocol,
        ) async throws -> AccountIdentityResponse {
            let request = WhoAmIRequestFactory.whoAmIRequest(auth: auth)
            let response = try await networkManager.asyncRequest(request)
            guard response.responseStatusCode >= 200, response.responseStatusCode < 300 else {
                throw response.asError()
            }
            return try JSONDecoder().decode(AccountIdentityResponse.self, from: response.responseBodyData ?? Data())
        }
    }
}
