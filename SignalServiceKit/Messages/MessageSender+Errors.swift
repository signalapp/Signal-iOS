//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum MessageSenderError: Error, IsRetryableProvider, UserErrorDescriptionProvider {
    case blockedContactRecipient
    case threadMissing

    public var localizedDescription: String {
        switch self {
        case .blockedContactRecipient:
            return OWSLocalizedString(
                "ERROR_DESCRIPTION_MESSAGE_SEND_FAILED_DUE_TO_BLOCK_LIST",
                comment: "Error message indicating that message send failed due to block list",
            )
        case .threadMissing:
            return OWSLocalizedString(
                "MESSAGE_STATUS_SEND_FAILED",
                comment: "Label indicating that a message failed to send.",
            )
        }
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool {
        switch self {
        case .blockedContactRecipient:
            return false
        case .threadMissing:
            return false
        }
    }
}

// MARK: -

extension Error {
    public var isFatalError: Bool {
        switch self {
        case is MessageSenderNoSessionForTransientMessageError:
            return true
        case is UntrustedIdentityError:
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

public class MessageSenderNoSuchSignalRecipientError: CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    public static let errorDomain = OWSError.errorDomain

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.noSuchSignalRecipient.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_UNREGISTERED_RECIPIENT",
            comment: "Error message when attempting to send message",
        )
    }

    public class func isNoSuchSignalRecipientError(_ error: Error?) -> Bool {
        error is MessageSenderNoSuchSignalRecipientError
    }

    public init() {}

    // MARK: - IsRetryableProvider

    // No need to retry if the recipient is not registered.
    public var isRetryableProvider: Bool { false }
}

// MARK: -

public class MessageSenderErrorNoValidRecipients: CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    static var asNSError: NSError {
        MessageSenderErrorNoValidRecipients() as Error as NSError
    }

    // NSError bridging: the domain of the error.
    public static let errorDomain = OWSError.errorDomain

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.messageSendNoValidRecipients.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_NO_VALID_RECIPIENTS",
            comment: "Error indicating that an outgoing message had no valid recipients.",
        )
    }

    public var isRetryableProvider: Bool { false }
}

// MARK: -

class MessageSenderNoSessionForTransientMessageError: CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    static let errorDomain = OWSError.errorDomain

    // NSError bridging: the error code within the given domain.
    var errorCode: Int { OWSErrorCode.noSessionForTransientMessage.rawValue }

    var isRetryableProvider: Bool { false }

    var localizedDescription: String {
        // These messages are never presented to the user, since these errors only
        // occur to transient messages. We only specify an error to avoid an assert.
        return OWSError.genericErrorDescription()
    }
}

// MARK: -

public class UntrustedIdentityError: CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    public let serviceId: ServiceId

    init(serviceId: ServiceId) {
        self.serviceId = serviceId
    }

    // NSError bridging: the domain of the error.
    public static let errorDomain = OWSError.errorDomain

    public static var errorCode: Int { OWSErrorCode.untrustedIdentity.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        let format = OWSLocalizedString(
            "FAILED_SENDING_BECAUSE_UNTRUSTED_IDENTITY_KEY",
            comment: "action sheet header when re-sending message which failed because of untrusted identity keys",
        )
        return String(format: format, SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(serviceId), tx: tx).resolvedValue()
        })
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { Self.errorCode }

    /// Key will continue to be unaccepted, so no need to retry. It'll only
    /// cause us to hit the Pre-Key request rate limit.
    public var isRetryableProvider: Bool { false }
}

public class InvalidKeySignatureError: CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    public let serviceId: ServiceId
    public let isTerminalFailure: Bool

    init(serviceId: ServiceId, isTerminalFailure: Bool) {
        self.serviceId = serviceId
        self.isTerminalFailure = isTerminalFailure
    }

    // NSError bridging: the domain of the error.
    public static let errorDomain = OWSError.errorDomain

    public static var errorCode: Int { OWSErrorCode.invalidKeySignature.rawValue }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        let format = OWSLocalizedString(
            "FAILED_SENDING_BECAUSE_INVALID_KEY_SIGNATURE",
            comment: "action sheet header when re-sending message which failed because of an invalid key signature",
        )
        return String(format: format, SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(serviceId), tx: tx).resolvedValue()
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

public class SpamChallengeRequiredError: CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    public static let errorDomain = OWSError.errorDomain

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    public var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_SUSPECTED_SPAM",
            comment: "Description for errors returned from the server due to suspected spam.",
        )
    }

    // NSError bridging: the error code within the given domain.
    public var errorCode: Int { OWSErrorCode.serverRejectedSuspectedSpam.rawValue }

    public var isRetryableProvider: Bool { false }
}

// MARK: -

class SpamChallengeResolvedError: CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {
    // NSError bridging: the domain of the error.
    static let errorDomain = OWSError.errorDomain

    // NSError bridging: the error code within the given domain.
    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.localizedDescription]
    }

    var localizedDescription: String {
        OWSLocalizedString(
            "ERROR_DESCRIPTION_SUSPECTED_SPAM",
            comment: "Description for errors returned from the server due to suspected spam.",
        )
    }

    // NSError bridging: the error code within the given domain.
    var errorCode: Int { OWSErrorCode.serverRejectedSuspectedSpam.rawValue }

    var isRetryableProvider: Bool { true }
}

// MARK: -

class OWSRetryableMessageSenderError: Error, IsRetryableProvider {
    static var asNSError: NSError {
        OWSRetryableMessageSenderError() as Error as NSError
    }

    // MARK: - IsRetryableProvider

    var isRetryableProvider: Bool { true }
}

// MARK: -

// NOTE: We typically prefer to use a more specific error.
class OWSUnretryableMessageSenderError: Error, IsRetryableProvider {
    static var asNSError: NSError {
        OWSUnretryableMessageSenderError() as Error as NSError
    }

    // MARK: - IsRetryableProvider

    var isRetryableProvider: Bool { false }
}

// MARK: -

class MessageDeletedBeforeSentError: CustomNSError, IsRetryableProvider {
    static var asNSError: NSError {
        MessageDeletedBeforeSentError() as Error as NSError
    }

    // NSError bridging: the domain of the error.
    static let errorDomain = OWSError.errorDomain

    // NSError bridging: the error code within the given domain.
    var errorCode: Int { OWSErrorCode.messageDeletedBeforeSent.rawValue }

    var isRetryableProvider: Bool { false }
}

// MARK: -

class MessageSendEncryptionError: CustomNSError, IsRetryableProvider {
    let serviceId: ServiceId
    let deviceId: DeviceId

    init(serviceId: ServiceId, deviceId: DeviceId) {
        self.serviceId = serviceId
        self.deviceId = deviceId
    }

    // NSError bridging: the domain of the error.
    static let errorDomain = OWSError.errorDomain

    // NSError bridging: the error code within the given domain.
    var errorCode: Int { OWSErrorCode.messageSendEncryptionFailure.rawValue }

    var isRetryableProvider: Bool { true }
}
