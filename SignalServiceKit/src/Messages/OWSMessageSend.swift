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

    // thread may be nil if message is an OWSOutgoingSyncMessage.
    @objc
    public let thread: TSThread?

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
    public var udAccess: OWSUDAccess?

    @objc
    public var senderCertificate: SMKSenderCertificate?

    @objc
    public let localNumber: String

    @objc
    public let isLocalNumber: Bool

    @objc
    public let success: () -> Void

    @objc
    public let failure: (Error) -> Void

    @objc
    public init(message: TSOutgoingMessage,
                thread: TSThread?,
                recipient: SignalRecipient,
                senderCertificate: SMKSenderCertificate?,
                udAccess: OWSUDAccess?,
                localNumber: String,
                success: @escaping () -> Void,
                failure: @escaping (Error) -> Void) {
        self.message = message
        self.thread = thread
        self.recipient = recipient
        self.localNumber = localNumber
        self.senderCertificate = senderCertificate
        self.udAccess = udAccess

        if let recipientId = recipient.uniqueId {
            self.isLocalNumber = localNumber == recipientId
        } else {
            owsFailDebug("SignalRecipient missing recipientId")
            self.isLocalNumber = false
        }

        self.success = success
        self.failure = failure
    }

    @objc
    public var isUDSend: Bool {
        return udAccess != nil && senderCertificate != nil
    }

    @objc
    public func disableUD() {
        Logger.verbose("\(String(describing: recipient.recipientId))")
        udAccess = nil
    }

    @objc
    public func setHasUDAuthFailed() {
        Logger.verbose("\(String(describing: recipient.recipientId))")
        // We "fail over" to non-UD sends after auth errors sending via UD.
        disableUD()
    }
}
