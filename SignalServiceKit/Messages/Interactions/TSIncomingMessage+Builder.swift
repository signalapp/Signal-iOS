//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

@objcMembers
public class TSIncomingMessageBuilder: TSMessageBuilder {
    @nonobjc
    public var authorAci: Aci?
    public var authorAciObjC: AciObjC? { authorAci.map { AciObjC($0) } }

    @nonobjc
    public var authorE164: E164?
    public var authorE164ObjC: E164ObjC? { authorE164.map { E164ObjC($0) } }

    public var read: Bool
    public var serverTimestamp: UInt64
    public var serverDeliveryTimestamp: UInt64
    public var serverGuid: String?
    public var wasReceivedByUD: Bool
    public var paymentNotification: TSPaymentNotification?

    @nonobjc
    public init(
        thread: TSThread,
        timestamp: UInt64?,
        receivedAtTimestamp: UInt64?,
        authorAci: Aci?,
        authorE164: E164?,
        messageBody: String?,
        bodyRanges: MessageBodyRanges?,
        editState: TSEditState,
        expiresInSeconds: UInt32,
        expireTimerVersion: UInt32?,
        expireStartedAt: UInt64,
        read: Bool,
        serverTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        serverGuid: String?,
        wasReceivedByUD: Bool,
        isSmsMessageRestoredFromBackup: Bool,
        isViewOnceMessage: Bool,
        isViewOnceComplete: Bool,
        wasRemotelyDeleted: Bool,
        storyAuthorAci: Aci?,
        storyTimestamp: UInt64?,
        storyReactionEmoji: String?,
        quotedMessage: TSQuotedMessage?,
        contactShare: OWSContact?,
        linkPreview: OWSLinkPreview?,
        messageSticker: MessageSticker?,
        giftBadge: OWSGiftBadge?,
        paymentNotification: TSPaymentNotification?
    ) {
        self.authorAci = authorAci
        self.authorE164 = authorE164
        self.read = read
        self.serverTimestamp = serverTimestamp
        self.serverDeliveryTimestamp = serverDeliveryTimestamp
        self.serverGuid = serverGuid
        self.wasReceivedByUD = wasReceivedByUD
        self.paymentNotification = paymentNotification

        super.init(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireTimerVersion: expireTimerVersion,
            expireStartedAt: expireStartedAt,
            isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup,
            isViewOnceMessage: isViewOnceMessage,
            isViewOnceComplete: isViewOnceComplete,
            wasRemotelyDeleted: wasRemotelyDeleted,
            storyAuthorAci: storyAuthorAci.map { AciObjC($0) },
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
            quotedMessage: quotedMessage,
            contactShare: contactShare,
            linkPreview: linkPreview,
            messageSticker: messageSticker,
            giftBadge: giftBadge
        )
    }

    @nonobjc
    public static func withDefaultValues(
        thread: TSThread,
        timestamp: UInt64? = nil,
        receivedAtTimestamp: UInt64? = nil,
        authorAci: Aci? = nil,
        authorE164: E164? = nil,
        messageBody: String? = nil,
        bodyRanges: MessageBodyRanges? = nil,
        editState: TSEditState = .none,
        expiresInSeconds: UInt32 = 0,
        expireTimerVersion: UInt32? = nil,
        expireStartedAt: UInt64 = 0,
        read: Bool = false,
        serverTimestamp: UInt64 = 0,
        serverDeliveryTimestamp: UInt64 = 0,
        serverGuid: String? = nil,
        wasReceivedByUD: Bool = false,
        isSmsMessageRestoredFromBackup: Bool = false,
        isViewOnceMessage: Bool = false,
        isViewOnceComplete: Bool = false,
        wasRemotelyDeleted: Bool = false,
        storyAuthorAci: Aci? = nil,
        storyTimestamp: UInt64? = nil,
        storyReactionEmoji: String? = nil,
        quotedMessage: TSQuotedMessage? = nil,
        contactShare: OWSContact? = nil,
        linkPreview: OWSLinkPreview? = nil,
        messageSticker: MessageSticker? = nil,
        giftBadge: OWSGiftBadge? = nil,
        paymentNotification: TSPaymentNotification? = nil
    ) -> TSIncomingMessageBuilder {
        return TSIncomingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            authorAci: authorAci,
            authorE164: authorE164,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireTimerVersion: expireTimerVersion,
            expireStartedAt: expireStartedAt,
            read: read,
            serverTimestamp: serverTimestamp,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            serverGuid: serverGuid,
            wasReceivedByUD: wasReceivedByUD,
            isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup,
            isViewOnceMessage: isViewOnceMessage,
            isViewOnceComplete: isViewOnceComplete,
            wasRemotelyDeleted: wasRemotelyDeleted,
            storyAuthorAci: storyAuthorAci,
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
            quotedMessage: quotedMessage,
            contactShare: contactShare,
            linkPreview: linkPreview,
            messageSticker: messageSticker,
            giftBadge: giftBadge,
            paymentNotification: paymentNotification
        )
    }

    // MARK: -

    private var hasBuilt = false

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
