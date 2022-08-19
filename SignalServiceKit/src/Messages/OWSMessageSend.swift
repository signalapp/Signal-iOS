//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

// Corresponds to a single effort to send a message to a given recipient,
// which may span multiple attempts.  Note that group messages may be sent
// to multiple recipients and therefore require multiple instances of
// OWSMessageSend.
@objc
public class OWSMessageSend: NSObject {
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
    public let address: SignalServiceAddress

    private static let kMaxRetriesPerRecipient: Int = 3

    private var _remainingAttempts = AtomicValue<Int>(OWSMessageSend.kMaxRetriesPerRecipient)
    @objc
    public var remainingAttempts: Int {
        get { return _remainingAttempts.get() }
        set { _remainingAttempts.set(newValue) }
    }

    // We "fail over" to REST sends after _any_ error sending
    // via the web socket.
    private var _hasWebsocketSendFailed = AtomicBool(false)
    @objc
    public var hasWebsocketSendFailed: Bool {
        get { return _hasWebsocketSendFailed.get() }
        set { _hasWebsocketSendFailed.set(newValue) }
    }

    private var _udSendingAccess = AtomicOptional<OWSUDSendingAccess>(nil)
    @objc
    public var udSendingAccess: OWSUDSendingAccess? {
        get { return _udSendingAccess.get() }
        set { _udSendingAccess.set(newValue) }
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
                address: SignalServiceAddress,
                udSendingAccess: OWSUDSendingAccess?,
                localAddress: SignalServiceAddress,
                sendErrorBlock: ((Error) -> Void)?) {
        self.message = message
        self.plaintextContent = plaintextContent
        self.plaintextPayloadId = plaintextPayloadId?.int64Value
        self.thread = thread
        self.address = address
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

    @objc
    public var isUDSend: Bool {
        return udSendingAccess != nil
    }

    @objc
    public func disableUD() {
        Logger.verbose("\(address)")
        udSendingAccess = nil
    }

    @objc
    public func setHasUDAuthFailed() {
        Logger.verbose("\(address)")
        // We "fail over" to non-UD sends after auth errors sending via UD.
        disableUD()
    }
}
