//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class OutgoingPinMessage: TSOutgoingMessage {
    public required init?(coder: NSCoder) {
        self.pinDurationForever = coder.decodeObject(of: NSNumber.self, forKey: "pinDurationForever")?.boolValue ?? false
        self.pinDurationSeconds = coder.decodeObject(of: NSNumber.self, forKey: "pinDurationSeconds")?.uint32Value ?? 0
        self.targetMessageAuthorAciBinary = coder.decodeObject(of: NSData.self, forKey: "targetMessageAuthorAciBinary") as Data?
        self.targetMessageTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "targetMessageTimestamp")?.uint64Value ?? 0
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.pinDurationForever), forKey: "pinDurationForever")
        coder.encode(NSNumber(value: self.pinDurationSeconds), forKey: "pinDurationSeconds")
        if let targetMessageAuthorAciBinary {
            coder.encode(targetMessageAuthorAciBinary, forKey: "targetMessageAuthorAciBinary")
        }
        coder.encode(NSNumber(value: self.targetMessageTimestamp), forKey: "targetMessageTimestamp")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(pinDurationForever)
        hasher.combine(pinDurationSeconds)
        hasher.combine(targetMessageAuthorAciBinary)
        hasher.combine(targetMessageTimestamp)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.pinDurationForever == object.pinDurationForever else { return false }
        guard self.pinDurationSeconds == object.pinDurationSeconds else { return false }
        guard self.targetMessageAuthorAciBinary == object.targetMessageAuthorAciBinary else { return false }
        guard self.targetMessageTimestamp == object.targetMessageTimestamp else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.pinDurationForever = self.pinDurationForever
        result.pinDurationSeconds = self.pinDurationSeconds
        result.targetMessageAuthorAciBinary = self.targetMessageAuthorAciBinary
        result.targetMessageTimestamp = self.targetMessageTimestamp
        return result
    }

    public private(set) var targetMessageTimestamp: UInt64 = 0
    public private(set) var targetMessageAuthorAciBinary: Data?
    public private(set) var pinDurationSeconds: UInt32 = 0
    private var pinDurationForever: Bool = false

    public init(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        targetMessageAuthorAciBinary: Aci,
        pinDurationSeconds: UInt32,
        pinDurationForever: Bool,
        messageExpiresInSeconds: UInt32,
        tx: DBReadTransaction,
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
            pinMessageBuilder.buildInfallibly(),
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

        let expiresAtMs: UInt64? = pinDurationSeconds > 0 ? Date.ows_millisecondTimestamp() + UInt64(pinDurationSeconds * 1000) : nil

        pinnedMessageManager.applyPinMessageChangeToLocalState(
            targetTimestamp: targetMessageTimestamp,
            targetAuthorAci: targetMessageAuthorAci,
            expiresAt: expiresAtMs,
            isPin: true,
            sentTimestamp: timestamp,
            tx: tx,
        )
    }
}
