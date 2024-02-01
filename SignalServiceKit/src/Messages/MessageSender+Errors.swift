//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum MessageSenderError: Error, IsRetryableProvider, UserErrorDescriptionProvider {
    case prekeyRateLimit
    case missingDevice
    case blockedContactRecipient
    case threadMissing

    public var localizedDescription: String {
        switch self {
        case .blockedContactRecipient:
            return OWSLocalizedString(
                "ERROR_DESCRIPTION_MESSAGE_SEND_FAILED_DUE_TO_BLOCK_LIST",
                comment: "Error message indicating that message send failed due to block list"
            )
        case .prekeyRateLimit, .missingDevice, .threadMissing:
            return OWSLocalizedString(
                "MESSAGE_STATUS_SEND_FAILED",
                comment: "Label indicating that a message failed to send."
            )
        }
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool {
        switch self {
        case .prekeyRateLimit:
            // TODO: Retry with backoff.
            // TODO: Can we honor a retry delay hint from the response?
            return true
        case .missingDevice:
            return true
        case .blockedContactRecipient:
            return false
        case .threadMissing:
            return false
        }
    }
}

// MARK: -

extension NSError {
    @objc
    public var shouldBeIgnoredForNonContactThreads: Bool {
        (self as Error).shouldBeIgnoredForNonContactThreads
    }
}

// MARK: -

extension Error {
    public var shouldBeIgnoredForNonContactThreads: Bool {
        self is MessageSenderNoSuchSignalRecipientError
    }
}

// MARK: -

extension NSError {
    @objc
    public var isFatalError: Bool { isFatalErrorImpl }

    fileprivate var isFatalErrorImpl: Bool {
        let error: Error = self as Error
        switch error {
        case is MessageSenderNoSessionForTransientMessageError:
            return true
        case is UntrustedIdentityError:
            return true
        case is SignalServiceRateLimitedError:
            // Avoid exacerbating the rate limiting.
            return true
        case is MessageDeletedBeforeSentError:
            return true
        default:
            // Default to NOT fatal.
            return false
        }
    }
}

// MARK: -

extension Error {
    public var isFatalError: Bool { (self as NSError).isFatalErrorImpl }
}

// MARK: -

@objc
public class MessageSenderNoSuchSignalRecipientError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.noSuchSignalRecipient.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_UNREGISTERED_RECIPIENT",
            comment: "Error message when attempting to send message"
        )
    }

    @objc
    public class func isNoSuchSignalRecipientError(_ error: Error?) -> Bool {
        error is MessageSenderNoSuchSignalRecipientError
    }

    // MARK: - IsRetryableProvider

    // No need to retry if the recipient is not registered.
    public var isRetryableProvider: Bool { false }
}

// MARK: -

@objc
class MessageSenderErrorNoValidRecipients: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    @objc
    public static var asNSError: NSError {
        MessageSenderErrorNoValidRecipients() as Error as NSError
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.messageSendNoValidRecipients.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_NO_VALID_RECIPIENTS",
            comment: "Error indicating that an outgoing message had no valid recipients."
        )
    }

    public var isRetryableProvider: Bool { false }
}

// MARK: -

class MessageSenderNoSessionForTransientMessageError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.noSessionForTransientMessage.rawValue }

    public var isRetryableProvider: Bool { false }

    public var localizedDescription: String {
        // These messages are never presented to the user, since these errors only
        // occur to transient messages. We only specify an error to avoid an assert.
        return OWSLocalizedString(
            "ERROR_DESCRIPTION_UNKNOWN_ERROR",
            comment: "Worst case generic error message"
        )
    }
}

// MARK: -

public class UntrustedIdentityError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    public let serviceId: ServiceId

    init(serviceId: ServiceId) {
        self.serviceId = serviceId
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    public static var errorCode: Int { OWSErrorCode.untrustedIdentity.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        let format = OWSLocalizedString(
            "FAILED_SENDING_BECAUSE_UNTRUSTED_IDENTITY_KEY",
            comment: "action sheet header when re-sending message which failed because of untrusted identity keys"
        )
        return String(format: format, databaseStorage.read { tx in
            return contactsManager.displayName(for: SignalServiceAddress(serviceId), transaction: tx)
        })
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { Self.errorCode }

    /// Key will continue to be unaccepted, so no need to retry. It'll only
    /// cause us to hit the Pre-Key request rate limit.
    public var isRetryableProvider: Bool { false }
}

public class InvalidKeySignatureError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    public let serviceId: ServiceId
    public let isTerminalFailure: Bool

    init(serviceId: ServiceId, isTerminalFailure: Bool) {
        self.serviceId = serviceId
        self.isTerminalFailure = isTerminalFailure
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    public static var errorCode: Int { OWSErrorCode.invalidKeySignature.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        let format = OWSLocalizedString(
            "FAILED_SENDING_BECAUSE_INVALID_KEY_SIGNATURE",
            comment: "action sheet header when re-sending message which failed because of an invalid key signature"
        )
        return String(format: format, databaseStorage.read { tx in
            return contactsManager.displayName(for: SignalServiceAddress(serviceId), transaction: tx)
        })
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { Self.errorCode }

    /// Key will continue to be invalidly signed, so no need to retry. It'll only
    /// cause us to hit the Pre-Key request rate limit.
    public var isRetryableProvider: Bool {
        !isTerminalFailure
    }
}

// MARK: -

class SignalServiceRateLimitedError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    @objc
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "FAILED_SENDING_BECAUSE_RATE_LIMIT",
            comment: "action sheet header when re-sending message which failed because of too many attempts"
        )
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.signalServiceRateLimited.rawValue }

    // We're already rate-limited. No need to exacerbate the problem.
    public var isRetryableProvider: Bool { false }
}

// MARK: -

@objc
class SpamChallengeRequiredError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    @objc
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_SUSPECTED_SPAM",
            comment: "Description for errors returned from the server due to suspected spam."
        )
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.serverRejectedSuspectedSpam.rawValue }

    public var isRetryableProvider: Bool { false }

    @objc
    public class func isSpamChallengeRequiredError(_ error: Error) -> Bool {
        error is SpamChallengeRequiredError
    }
}

// MARK: -

@objc
class SpamChallengeResolvedError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_SUSPECTED_SPAM",
            comment: "Description for errors returned from the server due to suspected spam."
        )
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.serverRejectedSuspectedSpam.rawValue }

    public var isRetryableProvider: Bool { true }

    @objc
    public class func isSpamChallengeResolvedError(_ error: Error) -> Bool {
        error is SpamChallengeResolvedError
    }
}

// MARK: -

@objc
class OWSRetryableMessageSenderError: NSObject, Error, IsRetryableProvider {
    @objc
    public static var asNSError: NSError {
        OWSRetryableMessageSenderError() as Error as NSError
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { true }
}

// MARK: -

// NOTE: We typically prefer to use a more specific error.
@objc
class OWSUnretryableMessageSenderError: NSObject, Error, IsRetryableProvider {
    @objc
    public static var asNSError: NSError {
        OWSUnretryableMessageSenderError() as Error as NSError
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { false }
}

// MARK: -

@objc
public class AppExpiredError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    @objc
    public static var asNSError: NSError {
        AppExpiredError() as Error as NSError
    }

    // NSError bridging: the domain of the error.
    @objc
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    @objc
    public static var errorCode: Int { OWSErrorCode.appExpired.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString("ERROR_SENDING_EXPIRED",
                          comment: "Error indicating a send failure due to an expired application.")
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { Self.errorCode }

    public var isRetryableProvider: Bool { false }
}

// MARK: -

@objc
public class AppDeregisteredError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    @objc
    public static var asNSError: NSError {
        AppDeregisteredError() as Error as NSError
    }

    // NSError bridging: the domain of the error.
    @objc
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    @objc
    public static var errorCode: Int { OWSErrorCode.appDeregistered.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? true
            ? OWSLocalizedString("ERROR_SENDING_DEREGISTERED",
                                comment: "Error indicating a send failure due to a deregistered application.")
            : OWSLocalizedString("ERROR_SENDING_DELINKED",
                                comment: "Error indicating a send failure due to a delinked application.")
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { Self.errorCode }

    public var isRetryableProvider: Bool { false }
}

// MARK: -

@objc
class MessageDeletedBeforeSentError: NSObject, CustomNSError, IsRetryableProvider {
    @objc
    public static var asNSError: NSError {
        MessageDeletedBeforeSentError() as Error as NSError
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.messageDeletedBeforeSent.rawValue }

    public var isRetryableProvider: Bool { false }
}

// MARK: -

class SenderKeyEphemeralError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    private let customLocalizedDescription: String

    init(customLocalizedDescription: String) {
        self.customLocalizedDescription = customLocalizedDescription
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.senderKeyEphemeralFailure.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String { customLocalizedDescription }

    public var isRetryableProvider: Bool { true }
}

// MARK: -

class SenderKeyUnavailableError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    private let customLocalizedDescription: String

    init(customLocalizedDescription: String) {
        self.customLocalizedDescription = customLocalizedDescription
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    public static var errorCode: Int { OWSErrorCode.senderKeyUnavailable.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { Self.errorCode }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String { customLocalizedDescription }

    /// These errors are retryable in the sense that a sent message can be
    /// retried and be successful, just not with sender key. If any intended
    /// recipient has previously failed with this error code in a prior send,
    /// the next send attempt will restrict itself to fanout send and not use
    /// sender key.
    public var isRetryableProvider: Bool { true }
}

// MARK: -

class MessageSendUnauthorizedError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.messageSendUnauthorized.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_SENDING_UNAUTHORIZED",
            comment: "Error message when attempting to send message"
        )
    }

    // No need to retry if we've been de-authed.
    public var isRetryableProvider: Bool { false }
}

// MARK: -

class MessageSendEncryptionError: NSObject, CustomNSError, IsRetryableProvider {
    public let serviceId: ServiceId
    public let deviceId: UInt32

    required init(serviceId: ServiceId, deviceId: UInt32) {
        self.serviceId = serviceId
        self.deviceId = deviceId
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String { OWSSignalServiceKitErrorDomain }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.messageSendEncryptionFailure.rawValue }

    public var isRetryableProvider: Bool { true }
}
