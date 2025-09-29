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
final public class TypingIndicatorMessage: TSOutgoingMessage {
    // Marked @objc so that Mantle can encode/decode it.
    @objc
    private var action: TypingIndicatorAction = .started

    // MARK: Initializers

    @objc
    public init(thread: TSThread,
                action: TypingIndicatorAction,
                transaction: DBReadTransaction) {
        self.action = action

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread)
        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: transaction
        )
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public override func shouldSyncTranscript() -> Bool {
        return false
    }

    @objc
    public override var isOnline: Bool {
        return true
    }

    @objc
    public override var isUrgent: Bool { false }

    private func protoAction(forAction action: TypingIndicatorAction) -> SSKProtoTypingMessageAction {
        switch action {
        case .started:
            return .started
        case .stopped:
            return .stopped
        }
    }

    public override func contentBuilder(thread: TSThread,
                                        transaction: DBReadTransaction) -> SSKProtoContentBuilder? {
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
    public override var shouldBeSaved: Bool {
        return false
    }

    @objc
    public override var debugDescription: String {
        return "typingIndicatorMessage"
    }

    @objc
    override var shouldRecordSendLog: Bool { false }

    @objc
    override var contentHint: SealedSenderContentHint { .implicit }
}
