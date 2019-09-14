//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

        super.init(outgoingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(),
                   in: thread,
                   messageBody: nil,
                   attachmentIds: NSMutableArray(),
                   expiresInSeconds: 0,
                   expireStartedAt: 0,
                   isVoiceMessage: false,
                   groupMetaMessage: .unspecified,
                   quotedMessage: nil,
                   contactShare: nil,
                   linkPreview: nil,
                   messageSticker: nil,
                   isViewOnceMessage: false)
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

    private func protoAction(forAction action: TypingIndicatorAction) -> SSKProtoTypingMessage.SSKProtoTypingMessageAction {
        switch action {
        case .started:
            return .started
        case .stopped:
            return .stopped
        }
    }

    @objc
    public override func buildPlainTextData(_ recipient: SignalRecipient) -> Data? {

        let typingBuilder = SSKProtoTypingMessage.builder(timestamp: self.timestamp)
        typingBuilder.setAction(protoAction(forAction: action))

        if let groupThread = self.threadWithSneakyTransaction as? TSGroupThread {
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

    // MARK: 

    @objc(stringForTypingIndicatorAction:)
    public class func string(forTypingIndicatorAction action: TypingIndicatorAction) -> String {
        switch action {
        case .started:
            return "started"
        case .stopped:
            return "stopped"
        }
    }
}
