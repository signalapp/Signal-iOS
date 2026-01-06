//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class OutgoingUnpinMessage: TSOutgoingMessage {
    public required init?(coder: NSCoder) {
        self.targetMessageAuthorAciBinary = coder.decodeObject(of: NSData.self, forKey: "targetMessageAuthorAciBinary") as Data?
        self.targetMessageTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "targetMessageTimestamp")?.uint64Value ?? 0
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let targetMessageAuthorAciBinary {
            coder.encode(targetMessageAuthorAciBinary, forKey: "targetMessageAuthorAciBinary")
        }
        coder.encode(NSNumber(value: self.targetMessageTimestamp), forKey: "targetMessageTimestamp")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(targetMessageAuthorAciBinary)
        hasher.combine(targetMessageTimestamp)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.targetMessageAuthorAciBinary == object.targetMessageAuthorAciBinary else { return false }
        guard self.targetMessageTimestamp == object.targetMessageTimestamp else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.targetMessageAuthorAciBinary = self.targetMessageAuthorAciBinary
        result.targetMessageTimestamp = self.targetMessageTimestamp
        return result
    }

    public private(set) var targetMessageTimestamp: UInt64 = 0
    public private(set) var targetMessageAuthorAciBinary: Data?

    public init(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        targetMessageAuthorAciBinary: Aci,
        messageExpiresInSeconds: UInt32,
        tx: DBReadTransaction,
    ) {
        self.targetMessageTimestamp = targetMessageTimestamp
        self.targetMessageAuthorAciBinary = targetMessageAuthorAciBinary.serviceIdBinary

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            expiresInSeconds: messageExpiresInSeconds,
        )

        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override public var shouldBeSaved: Bool { false }

    override var contentHint: SealedSenderContentHint { .implicit }

    override public func dataMessageBuilder(
        with thread: TSThread,
        transaction: DBReadTransaction,
    ) -> SSKProtoDataMessageBuilder? {
        guard
            let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci,
            thread.canUserEditPinnedMessages(aci: localAci)
        else {
            Logger.error("Local user no longer has permission to change pin status")
            return nil
        }

        guard
            let dataMessageBuilder = super.dataMessageBuilder(
                with: thread,
                transaction: transaction,
            )
        else {
            return nil
        }

        let unpinMessageBuilder = SSKProtoDataMessageUnpinMessage.builder()

        unpinMessageBuilder.setTargetSentTimestamp(targetMessageTimestamp)

        if let targetMessageAuthorAciBinary {
            unpinMessageBuilder.setTargetAuthorAciBinary(targetMessageAuthorAciBinary)
        }

        dataMessageBuilder.setUnpinMessage(
            unpinMessageBuilder.buildInfallibly(),
        )

        return dataMessageBuilder
    }

    override public func updateWithSendSuccess(tx: DBWriteTransaction) {
        let pinnedMessageManager = DependenciesBridge.shared.pinnedMessageManager

        guard
            let targetMessageAuthorAciBinary,
            let targetMessageAuthorAci = try? Aci.parseFrom(serviceIdBinary: targetMessageAuthorAciBinary)
        else {
            owsFailDebug("Couldn't parse ACI")
            return
        }

        pinnedMessageManager.applyPinMessageChangeToLocalState(
            targetTimestamp: targetMessageTimestamp,
            targetAuthorAci: targetMessageAuthorAci,
            expiresAt: nil,
            isPin: false,
            sentTimestamp: timestamp,
            tx: tx,
        )
    }
}
