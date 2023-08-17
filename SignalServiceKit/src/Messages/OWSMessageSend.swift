//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Provides parameters required for assembling a UD (sealed-sender) message.
@objc
public protocol UDSendingParamsProvider {
    /// Indicates desired behavior on the case of decryption error.
    var contentHint: SealedSenderContentHint { get }

    /// UD sending access, if available.
    var udSendingAccess: OWSUDSendingAccess? { get }

    /// Fetches a group ID to attache to the message envelope, to assist error
    /// handling in the case of decryption error.
    func envelopeGroupId(transaction: SDSAnyReadTransaction) -> Data?

    /// Disable UD auth. After this method is called, ``udSendingAccess``
    /// should return `nil`.
    func disableUDAuth()
}

// Corresponds to a single effort to send a message to a given recipient,
// which may span multiple attempts.  Note that group messages may be sent
// to multiple recipients and therefore require multiple instances of
// OWSMessageSend.
@objc
public class OWSMessageSend: NSObject, UDSendingParamsProvider {
    public let message: TSOutgoingMessage

    public let plaintextContent: Data

    public let plaintextPayloadId: Int64?

    public let thread: TSThread

    public let serviceId: ServiceId

    private static let kMaxRetriesPerRecipient: Int = 3

    private let _remainingAttempts = AtomicValue<Int>(OWSMessageSend.kMaxRetriesPerRecipient)
    public var remainingAttempts: Int {
        get { return _remainingAttempts.get() }
        set { _remainingAttempts.set(newValue) }
    }

    public let localIdentifiers: LocalIdentifiers

    public let promise: Promise<Void>

    public let success: () -> Void

    public let failure: (Error) -> Void

    public init(
        message: TSOutgoingMessage,
        plaintextContent: Data,
        plaintextPayloadId: Int64?,
        thread: TSThread,
        serviceId: ServiceId,
        udSendingAccess: OWSUDSendingAccess?,
        localIdentifiers: LocalIdentifiers,
        sendErrorBlock: ((Error) -> Void)?
    ) {
        self.message = message
        self.plaintextContent = plaintextContent
        self.plaintextPayloadId = plaintextPayloadId
        self.thread = thread
        self.serviceId = serviceId
        self.localIdentifiers = localIdentifiers

        let (promise, future) = Promise<Void>.pending()
        self.promise = promise
        self.success = {
            future.resolve()
        }
        self.failure = { error in
            if let sendErrorBlock = sendErrorBlock {
                sendErrorBlock(error)
            }
            future.reject(error)
        }

        super.init()

        self.udSendingAccess = udSendingAccess
    }

    // MARK: - UDSendingParamsProvider

    private var _udSendingAccess = AtomicOptional<OWSUDSendingAccess>(nil)
    public private(set) var udSendingAccess: OWSUDSendingAccess? {
        get { return _udSendingAccess.get() }
        set { _udSendingAccess.set(newValue) }
    }

    public var contentHint: SealedSenderContentHint {
        message.contentHint
    }

    public func envelopeGroupId(transaction: SDSAnyReadTransaction) -> Data? {
        message.envelopeGroupIdWithTransaction(transaction)
    }

    public func disableUDAuth() {
        udSendingAccess = nil
    }

    // MARK: - Getters

    public var isUDSend: Bool {
        return udSendingAccess != nil
    }
}
