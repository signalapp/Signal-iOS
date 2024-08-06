//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public class OWSOutgoingArchivedPaymentMessageBuilder: TSOutgoingMessageBuilder {

    @objc
    public var amount: String?
    @objc
    public var fee: String?
    @objc
    public var note: String?

    public required init(
        thread: TSThread,
        timestamp: UInt64?,
        amount: String?,
        fee: String?,
        note: String?,
        expirationStartedAt: UInt64?,
        expirationDurationSeconds: UInt32?
    ) {
        self.amount = amount
        self.fee = fee
        self.note = note
        super.init(
            thread: thread,
            timestamp: timestamp,
            messageBody: nil,
            bodyRanges: nil,
            editState: .none,
            expiresInSeconds: expirationDurationSeconds,
            expireStartedAt: expirationStartedAt,
            isVoiceMessage: false,
            groupMetaMessage: .unspecified,
            isViewOnceMessage: false,
            changeActionsProtoData: nil,
            storyAuthorAci: nil,
            storyTimestamp: nil,
            storyReactionEmoji: nil,
            giftBadge: nil
        )
    }

    public required init(thread: TSThread, timestamp: UInt64? = nil, messageBody: String? = nil, bodyRanges: MessageBodyRanges? = nil, editState: TSEditState = .none, expiresInSeconds: UInt32? = nil, expireStartedAt: UInt64? = nil, isVoiceMessage: Bool = false, groupMetaMessage: TSGroupMetaMessage = .unspecified, isViewOnceMessage: Bool = false, changeActionsProtoData: Data? = nil, storyAuthorAci: Aci? = nil, storyTimestamp: UInt64? = nil, storyReactionEmoji: String? = nil, giftBadge: OWSGiftBadge? = nil) {
        fatalError("init(thread:timestamp:messageBody:bodyRanges:editState:expiresInSeconds:expireStartedAt:isVoiceMessage:groupMetaMessage:isViewOnceMessage:changeActionsProtoData:storyAuthorAci:storyTimestamp:storyReactionEmoji:giftBadge:) has not been implemented")
    }
}
