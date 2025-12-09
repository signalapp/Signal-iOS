//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class OutgoingPinMessage: TSOutgoingMessage {
    @objc
    private var targetMessageTimestamp: UInt64 = 0

    @objc
    private var targetMessageAuthorAciBinary: Data?

    @objc
    private var pinDurationSeconds: UInt32 = 0

    @objc
    private var pinDurationForever: Bool = false

    public init(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        targetMessageAuthorAciBinary: Aci,
        pinDurationSeconds: UInt32,
        pinDurationForever: Bool,
        messageExpiresInSeconds: UInt32,
        tx: DBReadTransaction
    ) {
        self.targetMessageTimestamp = targetMessageTimestamp
        self.targetMessageAuthorAciBinary = targetMessageAuthorAciBinary.serviceIdBinary
        self.pinDurationSeconds = pinDurationSeconds
        self.pinDurationForever = pinDurationForever

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            expiresInSeconds: messageExpiresInSeconds,
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
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci,
              thread.canUserEditPinnedMessages(aci: localAci) else
        {
            Logger.error("Local user no longer has permission to change pin status")
            return nil
        }

        guard let dataMessageBuilder = super.dataMessageBuilder(
            with: thread,
            transaction: transaction
        ) else {
            return nil
        }

        let pinMessageBuilder = SSKProtoDataMessagePinMessage.builder()

        pinMessageBuilder.setTargetSentTimestamp(targetMessageTimestamp)

        if let targetMessageAuthorAciBinary {
            pinMessageBuilder.setTargetAuthorAciBinary(targetMessageAuthorAciBinary)
        }

        if pinDurationSeconds > 0 {
            pinMessageBuilder.setPinDurationSeconds(pinDurationSeconds)
        } else if pinDurationForever {
            pinMessageBuilder.setPinDurationForever(pinDurationForever)
        }

        dataMessageBuilder.setPinMessage(
            pinMessageBuilder.buildInfallibly()
        )

        return dataMessageBuilder
    }

    public override func updateWithSendSuccess(tx: DBWriteTransaction) {
        let pinnedMessageManager = DependenciesBridge.shared.pinnedMessageManager

        guard let targetMessageAuthorAciBinary,
                let targetMessageAuthorAci = try? Aci.parseFrom(serviceIdBinary: targetMessageAuthorAciBinary) else {
            owsFailDebug("Couldn't parse ACI")
            return
        }

        pinnedMessageManager.applyPinMessageChangeToLocalState(
            targetTimestamp: targetMessageTimestamp,
            targetAuthorAci: targetMessageAuthorAci,
            expiresAt: nil,
            isPin: true,
            tx: tx
        )
    }
}
