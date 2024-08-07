//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objcMembers
public class OWSOutgoingArchivedPaymentMessageBuilder: TSOutgoingMessageBuilder {
    public var amount: String?
    public var fee: String?
    public var note: String?

    public init(
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
            receivedAtTimestamp: nil,
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
}
