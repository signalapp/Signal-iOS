//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum OWSErrorCode: Int {
    case invalidMethodParameters = 11
    case obsolete12 = 12
    case failedToDecodeJson = 13
    case failedToEncodeJson = 14
    case failedToDecodeQR = 15
    case privacyVerificationFailure = 20
    case untrustedIdentity = 777427
    case invalidKeySignature = 777428
    case obsolete30 = 30
    case assertionFailure = 31
    case genericFailure = 32
    case failedToDecryptMessage = 100
    case failedToDecryptUDMessage = 101
    case failedToEncryptMessage = 110
    case failedToEncryptUDMessage = 111
    case messageSendUnauthorized = 1001
    case signalServiceRateLimited = 1010
    case userError = 2001
    case noSuchSignalRecipient = 777404
    case messageSendDisabledDueToPreKeyUpdateFailures = 777405
    case messageSendFailedToBlockList = 777406
    case messageSendNoValidRecipients = 777407
    case couldNotWriteAttachmentData = 777409
    case messageDeletedBeforeSent = 777410
    case databaseConversionFatalError = 777411
    case moveFileToSharedDataContainerError = 777412
    case debugLogUploadFailed = 777414
    // A non-recoverable error occurred while exporting a backup.
    case exportBackupFailed = 777415
    // A possibly recoverable error occurred while exporting a backup.
    case exportBackupError = 777416
    // A non-recoverable error occurred while importing a backup.
    case importBackupFailed = 777417
    // A possibly recoverable error occurred while importing a backup.
    case importBackupError = 777418
    // A non-recoverable while importing or exporting a backup.
    case backupFailure = 777419
    case localAuthenticationError = 777420
    case obsolete777421 = 777421
    case obsolete777422 = 777422
    case invalidMessage = 777423
    case profileUpdateFailed = 777424
    case avatarWriteFailed = 777425
    case avatarUploadFailed = 777426
    case invalidStickerData = 777429
    case attachmentDownloadFailed = 777430
    case appExpired = 777431
    case missingLocalThread = 777432
    case contactSyncFailed = 777433
    case appDeregistered = 777434
    case registrationTransferAvailable = 777435
    case failedToDecryptDuplicateMessage = 777436
    case serverRejectedSuspectedSpam = 777437
    case senderKeyEphemeralFailure = 777438
    case senderKeyUnavailable = 777439
    case messageSendEncryptionFailure = 777440
    case noSessionForTransientMessage = 777441  // NOTE: This value does not match the value before conversion to objc due to duplication of the raw value (was 777427 same as untrustedIdentity)
    case uploadFailed = 777442  // NOTE: This value does not match the value before conversion to objc due to duplication of the raw value (was 777428 same as invalidKeySignature)
}

@objc
public class OWSError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    public let errorCode: Int
    private let customLocalizedDescription: String
    private let customIsRetryable: Bool
    private var customUserInfo: [String: Any]?

    public init(errorCode: Int,
                description customLocalizedDescription: String,
                isRetryable customIsRetryable: Bool,
                userInfo customUserInfo: [String: Any]? = nil) {
        self.errorCode = errorCode
        self.customLocalizedDescription = customLocalizedDescription
        self.customIsRetryable = customIsRetryable
        self.customUserInfo = customUserInfo
    }

    public init(error: OWSErrorCode,
                description customLocalizedDescription: String,
                isRetryable customIsRetryable: Bool,
                userInfo customUserInfo: [String: Any]? = nil) {
        self.errorCode = error.rawValue
        self.customLocalizedDescription = customLocalizedDescription
        self.customIsRetryable = customIsRetryable
        self.customUserInfo = customUserInfo
    }

    public override var description: String {
        var result = "[OWSError code: \(errorCode), description: \(customLocalizedDescription)"
        if let customUserInfo = self.customUserInfo,
           !customUserInfo.isEmpty {
            result += ", userInfo: \(customUserInfo)"
        }
        result += "]"
        return result
    }

    // MARK: - CustomNSError

    // NSError bridging: the domain of the error.
    public static let errorDomain = "OWSSignalServiceKitErrorDomain"

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        var result: [String: Any] = customUserInfo ?? [:]
        result[NSLocalizedDescriptionKey] = customLocalizedDescription
        return result
    }

    public var localizedDescription: String { customLocalizedDescription }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { customIsRetryable }

    // MARK: - Old OWSError.h functions

    @available(swift, obsoleted: 1)
    @objc
    public static func makeAssertionError(_ description: String) -> NSError {
        owsFailDebug("Assertion failed: \(description)")
        return makeAssertionError() as Error as NSError
    }

    @inlinable
    public static func genericErrorDescription() -> String {
        OWSLocalizedString("ERROR_DESCRIPTION_UNKNOWN_ERROR", comment: "Worst case generic error message")
    }

    public static func makeAssertionError() -> OWSError {
        OWSError(error: .assertionFailure, description: genericErrorDescription(), isRetryable: false)
    }

    public static func makeGenericError() -> OWSError {
        OWSError(error: .genericFailure, description: genericErrorDescription(), isRetryable: false)
    }
}
