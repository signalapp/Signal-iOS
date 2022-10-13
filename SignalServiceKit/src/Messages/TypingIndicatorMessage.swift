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
public class TypingIndicatorMessage: TSOutgoingMessage {
    private let action: TypingIndicatorAction

    // MARK: Initializers

    @objc
    public init(thread: TSThread,
                action: TypingIndicatorAction,
                transaction: SDSAnyReadTransaction) {
        self.action = action

        let builder = TSOutgoingMessageBuilder(thread: thread)
        super.init(outgoingMessageWithBuilder: builder, transaction: transaction)
    }

    @objc
    public required init!(coder: NSCoder) {
        self.action = .started
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        self.action = .started
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
                                        transaction: SDSAnyReadTransaction) -> SSKProtoContentBuilder? {
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
