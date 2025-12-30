//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A message sent to the other participants of a group call to inform them that
/// some state has changed, such as we have joined or left the call.
///
/// Not to be confused with an ``OWSGroupCallMessage``.
@objc(OWSOutgoingGroupCallMessage)
public final class OutgoingGroupCallUpdateMessage: TSOutgoingMessage {
    public required init?(coder: NSCoder) {
        self.eraId = coder.decodeObject(of: NSString.self, forKey: "eraId") as String?
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let eraId {
            coder.encode(eraId, forKey: "eraId")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(eraId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.eraId == object.eraId else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.eraId = self.eraId
        return result
    }

    /// The era ID of the call with the update.
    private(set) var eraId: String?

    public init(
        thread: TSGroupThread,
        eraId: String?,
        tx: DBReadTransaction,
    ) {
        self.eraId = eraId

        super.init(
            outgoingMessageWith: .withDefaultValues(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override public var shouldBeSaved: Bool { false }

    override var contentHint: SealedSenderContentHint { .default }

    override public func dataMessageBuilder(
        with thread: TSThread,
        transaction: DBReadTransaction,
    ) -> SSKProtoDataMessageBuilder? {
        guard
            let dataMessageBuilder = super.dataMessageBuilder(
                with: thread,
                transaction: transaction,
            )
        else {
            return nil
        }

        let groupCallUpdateBuilder = SSKProtoDataMessageGroupCallUpdate.builder()

        if let eraId {
            groupCallUpdateBuilder.setEraID(eraId)
        }

        dataMessageBuilder.setGroupCallUpdate(
            groupCallUpdateBuilder.buildInfallibly(),
        )

        return dataMessageBuilder
    }
}
