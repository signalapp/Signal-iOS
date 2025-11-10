//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class OutgoingPollTerminateMessage: TSOutgoingMessage {

    @objc
    var targetPollTimestamp: UInt64 = 0

    public init(
        thread: TSGroupThread,
        targetPollTimestamp: UInt64,
        expiresInSeconds: UInt32 = 0,
        tx: DBReadTransaction
    ) {
        self.targetPollTimestamp = targetPollTimestamp
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            expiresInSeconds: expiresInSeconds,
        )

        super.init(
            outgoingMessageWith: builder,
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

        pollTerminateBuilder.setTargetSentTimestamp(targetPollTimestamp)

        dataMessageBuilder.setPollTerminate(
            pollTerminateBuilder.buildInfallibly()
        )

        return dataMessageBuilder
    }

    public override func updateWithAllSendingRecipientsMarkedAsFailed(
        error: (any Error)? = nil,
        transaction tx: DBWriteTransaction
    ) {
        super.updateWithAllSendingRecipientsMarkedAsFailed(error: error, transaction: tx)

        revertLocalStateIfFailedForEveryone(tx: tx)
    }

    private func revertLocalStateIfFailedForEveryone(tx: DBWriteTransaction) {
        // Do nothing if we successfully delivered to anyone. Only cleanup
        // local state if we fail to deliver to anyone.
        guard sentRecipientAddresses().isEmpty else {
            Logger.warn("Failed to send poll terminate to some recipients")
            return
        }

        Logger.error("Failed to send poll terminate to all recipients.")

        do {
            guard let targetMessage = try DependenciesBridge.shared.interactionStore.fetchMessage(
                timestamp: targetPollTimestamp,
                incomingMessageAuthor: nil,
                transaction: tx
            ),
                  let interactionId = targetMessage.grdbId?.int64Value
            else {
                Logger.error("Can't find target poll")
                return
            }

            try PollStore().revertPollTerminate(interactionId: interactionId, transaction: tx)

            // TODO: delete info message.

            SSKEnvironment.shared.databaseStorageRef.touch(interaction: targetMessage, shouldReindex: false, tx: tx)
        } catch {
            Logger.error("Failed to revert poll terminate: \(error)")
        }
    }
}
