//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class OutgoingPollTerminateMessage: TSOutgoingMessage {
    var targetPollTimestamp: UInt64?

    public init(
        thread: TSGroupThread,
        targetPollTimestamp: UInt64,
        tx: DBReadTransaction
    ) {
        self.targetPollTimestamp = targetPollTimestamp
        super.init(
            outgoingMessageWith: .withDefaultValues(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx
        )
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required public init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    override public var shouldBeSaved: Bool { false }

    override var contentHint: SealedSenderContentHint { .implicit }

    override public func dataMessageBuilder(
        with thread: TSThread,
        transaction: DBReadTransaction
    ) -> SSKProtoDataMessageBuilder? {
        guard let dataMessageBuilder = super.dataMessageBuilder(
            with: thread,
            transaction: transaction
        ) else {
            return nil
        }

        let pollTerminateBuilder = SSKProtoDataMessagePollTerminate.builder()

        if let targetPollTimestamp {
            pollTerminateBuilder.setTargetSentTimestamp(targetPollTimestamp)
        }

        dataMessageBuilder.setPollTerminate(
            pollTerminateBuilder.buildInfallibly()
        )

        if !FeatureFlags.pollKeepProtoVersion {
            dataMessageBuilder.setRequiredProtocolVersion(UInt32(SSKProtoDataMessageProtocolVersion.polls.rawValue))
        }

        return dataMessageBuilder
    }
}
