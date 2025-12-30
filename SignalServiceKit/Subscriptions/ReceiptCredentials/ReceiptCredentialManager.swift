//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

/// Responsible for `ReceiptCredential` operations, which are part of redeeming
/// all zero-knowledge subscriptions (donations and Backups).
public struct ReceiptCredentialManager {
    private let dateProvider: DateProvider
    private let logger: PrefixedLogger
    private let networkManager: NetworkManager

    init(
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger,
        networkManager: NetworkManager,
    ) {
        self.dateProvider = dateProvider
        self.logger = logger
        self.networkManager = networkManager
    }

    public static func generateReceiptCredentialPresentation(
        receiptCredential: ReceiptCredential,
    ) throws -> ReceiptCredentialPresentation {
        return try clientZKReceiptOperations().createReceiptCredentialPresentation(
            receiptCredential: receiptCredential,
        )
    }

    public static func generateReceiptRequest() -> (
        context: ReceiptCredentialRequestContext,
        request: ReceiptCredentialRequest,
    ) {
        do {
            let clientOperations = clientZKReceiptOperations()
            let receiptSerial = try generateReceiptSerial()

            let receiptCredentialRequestContext = try clientOperations.createReceiptCredentialRequestContext(receiptSerial: receiptSerial)
            let receiptCredentialRequest = try receiptCredentialRequestContext.getRequest()
            return (receiptCredentialRequestContext, receiptCredentialRequest)
        } catch {
            // This operation happens entirely on-device and is unlikely to fail.
            // If it does, a full crash is probably desirable.
            owsFail("Could not generate receipt request: \(error)")
        }
    }

    // MARK: -

    public func requestReceiptCredential(
        via networkRequest: TSRequest,
        isValidReceiptLevelPredicate: @escaping (UInt64) -> Bool,
        context: ReceiptCredentialRequestContext,
    ) async throws -> ReceiptCredential {
        do {
            let response = try await networkManager.asyncRequest(networkRequest)

            return try self.parseReceiptCredentialResponse(
                httpResponse: response,
                receiptCredentialRequestContext: context,
                isValidReceiptLevelPredicate: isValidReceiptLevelPredicate,
            )
        } catch {
            throw parseReceiptCredentialPresentationError(error: error)
        }
    }

    private func parseReceiptCredentialResponse(
        httpResponse: HTTPResponse,
        receiptCredentialRequestContext: ReceiptCredentialRequestContext,
        isValidReceiptLevelPredicate: (UInt64) -> Bool,
    ) throws -> ReceiptCredential {
        let clientOperations = Self.clientZKReceiptOperations()

        let httpStatusCode = httpResponse.responseStatusCode
        switch httpStatusCode {
        case 200:
            logger.info("Got valid receipt response.")
        case 204:
            logger.info("No receipt yet, payment processing.")
            throw ReceiptCredentialRequestError(
                errorCode: .paymentStillProcessing,
            )
        default:
            throw OWSAssertionError(
                "Unexpected success status code: \(httpStatusCode)",
                logger: logger,
            )
        }

        func failValidation(_ message: String) -> Error {
            owsFailDebug(message, logger: logger)
            return ReceiptCredentialRequestError(errorCode: .localValidationFailed)
        }

        guard
            let parser = httpResponse.responseBodyParamParser,
            let receiptCredentialResponseData = Data(
                base64Encoded: try parser.required(key: "receiptCredentialResponse") as String,
            )
        else {
            throw failValidation("Failed to parse receipt credential response into data!")
        }

        let receiptCredentialResponse = try ReceiptCredentialResponse(
            contents: receiptCredentialResponseData,
        )
        let receiptCredential = try clientOperations.receiveReceiptCredential(
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialResponse: receiptCredentialResponse,
        )

        let receiptLevel = try receiptCredential.getReceiptLevel()
        guard isValidReceiptLevelPredicate(receiptLevel) else {
            throw failValidation("Unexpected receipt credential level! \(receiptLevel)")
        }

        // Validate receipt credential expiration % 86400 == 0, per server spec
        let expiration = try receiptCredential.getReceiptExpirationTime()
        guard expiration % 86400 == 0 else {
            throw failValidation("Invalid receipt credential expiration! \(expiration)")
        }

        // Validate expiration is less than 90 days from now
        let maximumValidExpirationDate = dateProvider().addingTimeInterval(90 * .day)
        guard Date(timeIntervalSince1970: TimeInterval(expiration)) < maximumValidExpirationDate else {
            throw failValidation("Invalid receipt credential expiration!")
        }

        return receiptCredential
    }

    private func parseReceiptCredentialPresentationError(
        error: Error,
    ) -> Error {
        guard
            let httpStatusCode = error.httpStatusCode,
            let errorCode = ReceiptCredentialRequestError.ErrorCode(rawValue: httpStatusCode)
        else { return error }

        if
            case .paymentFailed = errorCode,
            let httpResponseData = error.httpResponseData,
            let httpResponseDict = try? JSONSerialization.jsonObject(with: httpResponseData) as? [String: Any],
            let chargeFailureDict = httpResponseDict["chargeFailure"] as? [String: Any],
            let chargeFailureCode = chargeFailureDict["code"] as? String
        {
            return ReceiptCredentialRequestError(
                errorCode: errorCode,
                chargeFailureCodeIfPaymentFailed: chargeFailureCode,
            )
        }

        return ReceiptCredentialRequestError(errorCode: errorCode)
    }

    // MARK: -

    private static func generateReceiptSerial() throws -> ReceiptSerial {
        let count = ReceiptSerial.SIZE
        let bytes = Randomness.generateRandomBytes(UInt(count))
        return try ReceiptSerial(contents: bytes)
    }

    private static func clientZKReceiptOperations() -> ClientZkReceiptOperations {
        let params = GroupsV2Protos.serverPublicParams()
        return ClientZkReceiptOperations(serverPublicParams: params)
    }
}
