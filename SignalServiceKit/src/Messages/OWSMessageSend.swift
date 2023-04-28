//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
    @objc
    public let message: TSOutgoingMessage

    @objc
    public var plaintextContent: Data?

    @objc(plaintextPayloadId)
    @available(swift, obsoleted: 1.0)
    public var plaintextPayloadIdObjc: NSNumber? { plaintextPayloadId.map { NSNumber(value: $0) } }
    public var plaintextPayloadId: Int64?

    @objc
    public let thread: TSThread

    @objc
    public let serviceId: ServiceIdObjC

    @objc
    public let address: SignalServiceAddress

    private static let kMaxRetriesPerRecipient: Int = 3

    private var _remainingAttempts = AtomicValue<Int>(OWSMessageSend.kMaxRetriesPerRecipient)
    @objc
    public var remainingAttempts: Int {
        get { return _remainingAttempts.get() }
        set { _remainingAttempts.set(newValue) }
    }

    @objc
    public let localAddress: SignalServiceAddress

    @objc
    public let isLocalAddress: Bool

    public let promise: Promise<Void>

    @objc
    public var asAnyPromise: AnyPromise {
        return AnyPromise(promise)
    }

    @objc
    public let success: () -> Void

    @objc
    public let failure: (Error) -> Void

    @objc
    public init(message: TSOutgoingMessage,
                plaintextContent: Data?,
                plaintextPayloadId: NSNumber?,
                thread: TSThread,
                serviceId: ServiceIdObjC,
                udSendingAccess: OWSUDSendingAccess?,
                localAddress: SignalServiceAddress,
                sendErrorBlock: ((Error) -> Void)?) {
        self.message = message
        self.plaintextContent = plaintextContent
        self.plaintextPayloadId = plaintextPayloadId?.int64Value
        self.thread = thread
        self.serviceId = serviceId
        self.address = SignalServiceAddress(serviceId.wrappedValue)
        self.localAddress = localAddress
        self.isLocalAddress = address.isLocalAddress

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
    @objc
    public private(set) var udSendingAccess: OWSUDSendingAccess? {
        get { return _udSendingAccess.get() }
        set { _udSendingAccess.set(newValue) }
    }

    @objc
    public var contentHint: SealedSenderContentHint {
        message.contentHint
    }

    @objc
    public func envelopeGroupId(transaction: SDSAnyReadTransaction) -> Data? {
        message.envelopeGroupIdWithTransaction(transaction)
    }

    @objc
    public func disableUDAuth() {
        udSendingAccess = nil
    }

    // MARK: - Getters

    @objc
    public var isUDSend: Bool {
        return udSendingAccess != nil
    }
}
