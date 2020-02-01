//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMetadataKit

// Corresponds to a single effort to send a message to a given recipient,
// which may span multiple attempts.  Note that group messages may be sent
// to multiple recipients and therefore require multiple instances of
// OWSMessageSend.
@objc
public class OWSMessageSend: NSObject {
    @objc
    public let message: TSOutgoingMessage

    @objc
    public let thread: TSThread

    @objc
    public let recipient: SignalRecipient

    private static let kMaxRetriesPerRecipient: Int = 3

    @objc
    public var remainingAttempts = OWSMessageSend.kMaxRetriesPerRecipient

    // We "fail over" to REST sends after _any_ error sending
    // via the web socket.
    @objc
    public var hasWebsocketSendFailed = false

    @objc
    public var udSendingAccess: OWSUDSendingAccess?

    @objc
    public let localAddress: SignalServiceAddress

    @objc
    public let isLocalAddress: Bool

    @objc
    public let success: () -> Void

    @objc
    public let failure: (Error) -> Void

    @objc
    public init(message: TSOutgoingMessage,
                thread: TSThread,
                recipient: SignalRecipient,
                udSendingAccess: OWSUDSendingAccess?,
                localAddress: SignalServiceAddress,
                success: @escaping () -> Void,
                failure: @escaping (Error) -> Void) {
        self.message = message
        self.thread = thread
        self.recipient = recipient
        self.localAddress = localAddress
        self.udSendingAccess = udSendingAccess
        self.isLocalAddress = recipient.address.isLocalAddress

        self.success = success
        self.failure = failure
    }

    @objc
    public var isUDSend: Bool {
        return udSendingAccess != nil
    }

    @objc
    public func disableUD() {
        Logger.verbose("\(recipient.address)")
        udSendingAccess = nil
    }

    @objc
    public func setHasUDAuthFailed() {
        Logger.verbose("\(recipient.address)")
        // We "fail over" to non-UD sends after auth errors sending via UD.
        disableUD()
    }
}
