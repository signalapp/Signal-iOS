//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSTypingIndicatorAction)
public enum TypingIndicatorAction: Int {
    case started
    case stopped
}

@objc(OWSTypingIndicatorMessage)
public final class TypingIndicatorMessage: TSOutgoingMessage {
    public required init?(coder: NSCoder) {
        self.action = (coder.decodeObject(of: NSNumber.self, forKey: "action")?.intValue).flatMap(TypingIndicatorAction.init(rawValue:)) ?? .started
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.action.rawValue), forKey: "action")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(action)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.action == object.action else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.action = self.action
        return result
    }

    private var action: TypingIndicatorAction = .started

    // MARK: Initializers

    @objc
    public init(
        thread: TSThread,
        action: TypingIndicatorAction,
        transaction: DBReadTransaction,
    ) {
        self.action = action

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread)
        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: transaction,
        )
    }

    @objc
    override public func shouldSyncTranscript() -> Bool {
        return false
    }

    @objc
    override public var isOnline: Bool {
        return true
    }

    @objc
    override public var isUrgent: Bool { false }

    private func protoAction(forAction action: TypingIndicatorAction) -> SSKProtoTypingMessageAction {
        switch action {
        case .started:
            return .started
        case .stopped:
            return .stopped
        }
    }

    override public func contentBuilder(
        thread: TSThread,
        transaction: DBReadTransaction,
    ) -> SSKProtoContentBuilder? {
        let typingBuilder = SSKProtoTypingMessage.builder(timestamp: self.timestamp)
        typingBuilder.setAction(protoAction(forAction: action))

        if let groupThread = thread as? TSGroupThread {
            typingBuilder.setGroupID(groupThread.groupModel.groupId)
        }

        let contentBuilder = SSKProtoContent.builder()

        do {
            contentBuilder.setTypingMessage(try typingBuilder.build())
            return contentBuilder
        } catch let error {
            owsFailDebug("failed to build protobuf: \(error)")
            return nil
        }
    }

    // MARK: TSYapDatabaseObject overrides

    @objc
    override public var shouldBeSaved: Bool {
        return false
    }

    @objc
    override public var debugDescription: String {
        return "typingIndicatorMessage"
    }

    @objc
    override var shouldRecordSendLog: Bool { false }

    @objc
    override var contentHint: SealedSenderContentHint { .implicit }
}
