//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMetadataKit

@objc
public class OWSMessageSend: NSObject {
    @objc
    public let message: TSOutgoingMessage

    // thread may be nil if message is an OWSOutgoingSyncMessage.
    @objc
    public let thread: TSThread?

    @objc
    public let recipient: SignalRecipient

    // TODO: Should this be per-recipient or per-message?
    private static let kMaxRetriesPerRecipient: Int = 3

    @objc
    public var remainingAttempts = OWSMessageSend.kMaxRetriesPerRecipient

    // We "fail over" to REST sends after _any_ error sending
    // via the web socket.
    @objc
    public var useWebsocketIfAvailable = true

    // We "fail over" to non-UD sends after certain errors sending
    // via UD.
    @objc
    public var canUseUD = true

    @objc
    public let udAccessKey: SMKUDAccessKey?

    @objc
    public let localNumber: String

    @objc
    public let isLocalNumber: Bool

    @objc
    public let senderCertificate: SMKSenderCertificate?

    @objc
    public init(message: TSOutgoingMessage,
                thread: TSThread?,
                recipient: SignalRecipient,
                senderCertificate: SMKSenderCertificate?,
                udManager: OWSUDManager,
                localNumber: String) {
        self.message = message
        self.thread = thread
        self.recipient = recipient
        self.senderCertificate = senderCertificate

        var udAccessKey: SMKUDAccessKey?
        var isLocalNumber: Bool = false
        if let recipientId = recipient.uniqueId {
            udAccessKey = udManager.udAccessKeyForRecipient(recipientId)
            isLocalNumber = localNumber == recipientId
        } else {
            owsFailDebug("SignalRecipient missing recipientId")
        }
        self.udAccessKey = udAccessKey
        self.localNumber = localNumber
        self.isLocalNumber = isLocalNumber
    }
}
