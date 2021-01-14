//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
                action: TypingIndicatorAction) {
        self.action = action

        let builder = TSOutgoingMessageBuilder(thread: thread)
        super.init(outgoingMessageWithBuilder: builder)
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
    public override var isSilent: Bool {
        return true
    }

    @objc
    public override var isOnline: Bool {
        return true
    }

    private func protoAction(forAction action: TypingIndicatorAction) -> SSKProtoTypingMessageAction {
        switch action {
        case .started:
            return .started
        case .stopped:
            return .stopped
        }
    }

    @objc
    public override func buildPlainTextData(_ address: SignalServiceAddress,
                                            thread: TSThread,
                                            transaction: SDSAnyReadTransaction) -> Data? {

        let typingBuilder = SSKProtoTypingMessage.builder(timestamp: self.timestamp)
        typingBuilder.setAction(protoAction(forAction: action))

        if let groupThread = thread as? TSGroupThread {
            typingBuilder.setGroupID(groupThread.groupModel.groupId)
        }

        let contentBuilder = SSKProtoContent.builder()

        do {
            contentBuilder.setTypingMessage(try typingBuilder.build())

            let data = try contentBuilder.buildSerializedData()
            return data
        } catch let error {
            owsFailDebug("failed to build content: \(error)")
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
}
