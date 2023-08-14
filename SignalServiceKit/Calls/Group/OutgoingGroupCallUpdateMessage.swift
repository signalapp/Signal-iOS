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
    /// The era ID of the call with the update.
    ///
    /// - Note
    /// Nullable and `var` to play nice with Mantle, which will set this during
    /// its `init(coder:)`.
    @objc
    private(set) var eraId: String?

    public init(
        thread: TSGroupThread,
        eraId: String?,
        tx: SDSAnyReadTransaction
    ) {
        self.eraId = eraId

        super.init(
            outgoingMessageWithBuilder: TSOutgoingMessageBuilder(thread: thread),
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

    override var contentHint: SealedSenderContentHint { .default }

    override public func dataMessageBuilder(
        with thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> SSKProtoDataMessageBuilder? {
        guard let dataMessageBuilder = super.dataMessageBuilder(
            with: thread,
            transaction: transaction
        ) else {
            return nil
        }

        let groupCallUpdateBuilder = SSKProtoDataMessageGroupCallUpdate.builder()

        if let eraId {
            groupCallUpdateBuilder.setEraID(eraId)
        }

        dataMessageBuilder.setGroupCallUpdate(
            groupCallUpdateBuilder.buildInfallibly()
        )

        return dataMessageBuilder
    }
}
