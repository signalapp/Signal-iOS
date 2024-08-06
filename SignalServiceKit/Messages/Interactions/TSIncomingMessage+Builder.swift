//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public class TSIncomingMessageBuilder: TSMessageBuilder {
    public var authorAci: Aci?
    @objc
    public var authorAciObjC: AciObjC? { authorAci.map { AciObjC($0) } }

    public var authorE164: E164?
    @objc
    public var authorE164ObjC: E164ObjC? { authorE164.map { E164ObjC($0) } }

    @objc
    public var serverTimestamp: NSNumber?
    @objc
    public var serverDeliveryTimestamp: UInt64 = 0
    @objc
    public var serverGuid: String?
    @objc
    public var wasReceivedByUD = false
    @objc
    public var paymentNotification: TSPaymentNotification?

    public init(
        thread: TSThread,
        timestamp: UInt64?,
        authorAci: Aci?,
        authorE164: E164?,
        messageBody: String?,
        bodyRanges: MessageBodyRanges?,
        editState: TSEditState,
        expiresInSeconds: UInt32,
        expireStartedAt: UInt64,
        read: Bool,
        serverTimestamp: NSNumber?,
        serverDeliveryTimestamp: UInt64,
        serverGuid: String?,
        wasReceivedByUD: Bool,
        isViewOnceMessage: Bool,
        storyAuthorAci: Aci?,
        storyTimestamp: UInt64?,
        storyReactionEmoji: String?,
        giftBadge: OWSGiftBadge?,
        paymentNotification: TSPaymentNotification?
    ) {
        super.init(
            thread: thread,
            timestamp: timestamp,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireStartedAt: expireStartedAt,
            isViewOnceMessage: isViewOnceMessage,
            read: read,
            storyAuthorAci: storyAuthorAci.map { AciObjC($0) },
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
            giftBadge: giftBadge
        )

        self.authorAci = authorAci
        self.authorE164 = authorE164
        self.serverTimestamp = serverTimestamp
        self.serverDeliveryTimestamp = serverDeliveryTimestamp
        self.serverGuid = serverGuid
        self.wasReceivedByUD = wasReceivedByUD
        self.paymentNotification = paymentNotification
    }

    public static func withDefaultValues(
        thread: TSThread,
        timestamp: UInt64? = nil,
        authorAci: Aci? = nil,
        authorE164: E164? = nil,
        messageBody: String? = nil,
        bodyRanges: MessageBodyRanges? = nil,
        editState: TSEditState = .none,
        expiresInSeconds: UInt32 = 0,
        expireStartedAt: UInt64 = 0,
        read: Bool = false,
        serverTimestamp: NSNumber? = nil,
        serverDeliveryTimestamp: UInt64 = 0,
        serverGuid: String? = nil,
        wasReceivedByUD: Bool = false,
        isViewOnceMessage: Bool = false,
        storyAuthorAci: Aci? = nil,
        storyTimestamp: UInt64? = nil,
        storyReactionEmoji: String? = nil,
        giftBadge: OWSGiftBadge? = nil,
        paymentNotification: TSPaymentNotification? = nil
    ) -> TSIncomingMessageBuilder {
        return TSIncomingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            authorAci: authorAci,
            authorE164: authorE164,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireStartedAt: expireStartedAt,
            read: read,
            serverTimestamp: serverTimestamp,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            serverGuid: serverGuid,
            wasReceivedByUD: wasReceivedByUD,
            isViewOnceMessage: isViewOnceMessage,
            storyAuthorAci: storyAuthorAci,
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
            giftBadge: giftBadge,
            paymentNotification: paymentNotification
        )
    }

    // MARK: -

    private var hasBuilt = false

    @objc
    public func build() -> TSIncomingMessage {
        if hasBuilt {
            owsFailDebug("Don't build more than once.")
        }
        hasBuilt = true

        if let paymentNotification {
            return OWSIncomingPaymentMessage(
                initIncomingMessageWithBuilder: self,
                paymentNotification: paymentNotification
            )
        }

        return TSIncomingMessage(incomingMessageWithBuilder: self)
    }
}
