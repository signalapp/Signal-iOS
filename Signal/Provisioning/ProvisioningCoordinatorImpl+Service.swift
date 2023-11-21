//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension ProvisioningCoordinatorImpl {

    enum Service {

        enum VerifySecondaryDeviceResponse {
            case success(ProvisioningServiceResponses.VerifySecondaryDeviceResponse)
            case obsoleteLinkedDevice
            case deviceLimitExceeded(DeviceLimitExceededError)
            case genericError(Error)
        }

        static func makeVerifySecondaryDeviceRequest(
            verificationCode: String,
            phoneNumber: String,
            authPassword: String,
            accountAttributes: AccountAttributes,
            apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
            prekeyBundles: RegistrationPreKeyUploadBundles,
            signalService: OWSSignalServiceProtocol
        ) async -> VerifySecondaryDeviceResponse {
            let request = ProvisioningRequestFactory.verifySecondaryDeviceRequest(
                verificationCode: verificationCode,
                phoneNumber: phoneNumber,
                authPassword: authPassword,
                attributes: accountAttributes,
                apnRegistrationId: apnRegistrationId,
                prekeyBundles: prekeyBundles
            )

            do {
                let response = try await signalService.urlSessionForMainSignalService()
                    .promiseForTSRequest(request)
                    .awaitable()
                return handleVerifySecondaryDeviceResponse(
                    statusCode: response.responseStatusCode,
                    retryAfterHeader: response.responseHeaders[Constants.retryAfterHeader],
                    bodyData: response.responseBodyData
                )
            } catch {
                if error.isNetworkFailureOrTimeout {
                    return .genericError(error)
                }
                guard let error = error as? OWSHTTPError else {
                    return .genericError(error)
                }
                return handleVerifySecondaryDeviceResponse(
                    statusCode: error.responseStatusCode,
                    retryAfterHeader: error.responseHeaders?.value(forHeader: Constants.retryAfterHeader),
                    bodyData: error.httpResponseData
                )
            }
        }

        private static func handleVerifySecondaryDeviceResponse(
            statusCode: Int,
            retryAfterHeader: String?,
            bodyData: Data?
        ) -> VerifySecondaryDeviceResponse {
            let statusCode = ProvisioningServiceResponses.VerifySecondaryDeviceResponseCodes(rawValue: statusCode)
            switch statusCode {
            case .success:
                guard let bodyData else {
                    return .genericError(OWSAssertionError("Got empty verify secondary device response"))
                }
                guard let response = try? JSONDecoder().decode(
                    ProvisioningServiceResponses.VerifySecondaryDeviceResponse.self,
                    from: bodyData
                ) else {
                    return .genericError(OWSAssertionError("Unable to parse verify secondary device response from response"))
                }

                return .success(response)
            case .obsoleteLinkedDevice:
                Logger.warn("Obsolete linked device response")
                return .obsoleteLinkedDevice
            case .deviceLimitExceeded:
                Logger.warn("Device limit exceeded")
                return .deviceLimitExceeded(DeviceLimitExceededError())
            case .none, .unexpectedError:
                return .genericError(OWSAssertionError("Unknown status code"))
            }
        }

        static func makeUpdateSecondaryDeviceCapabilitiesRequest(
            capabilities: AccountAttributes.Capabilities,
            auth: ChatServiceAuth,
            signalService: OWSSignalServiceProtocol,
            tsAccountManager: TSAccountManager
        ) async throws {
            let request = AccountAttributesRequestFactory.updateLinkedDeviceCapabilitiesRequest(
                capabilities,
                tsAccountManager: tsAccountManager
            )
            request.setAuth(auth)

            // Don't care what the response is.
            _ = try await signalService.urlSessionForMainSignalService()
                .promiseForTSRequest(request)
                .awaitable()
        }

        enum Constants {
            static let defaultRetryTime: TimeInterval = 3

            static let retryAfterHeader = "retry-after"
        }
    }
}
