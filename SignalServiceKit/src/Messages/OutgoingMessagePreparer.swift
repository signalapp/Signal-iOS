//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@objc
public class OutgoingMessagePreparer: NSObject {

    public let message: TSOutgoingMessage
    private let unsavedAttachmentInfos: [OutgoingAttachmentInfo]
    private var didCompletePrep = false

    @objc
    public var savedAttachmentIds: [String]?

    public var unpreparedMessage: TSOutgoingMessage {
        assert(!didCompletePrep)
        return message
    }

    @objc
    public convenience init(_ message: TSOutgoingMessage) {
        self.init(message, unsavedAttachmentInfos: [])
    }

    @objc
    public init(_ message: TSOutgoingMessage, unsavedAttachmentInfos: [OutgoingAttachmentInfo]) {
        self.message = message
        self.unsavedAttachmentInfos = unsavedAttachmentInfos
    }

    public func insertMessage(linkPreviewDraft: OWSLinkPreviewDraft? = nil,
                              transaction: SDSAnyWriteTransaction) {
        unpreparedMessage.anyInsert(transaction: transaction)
        if let linkPreviewDraft = linkPreviewDraft {
            do {
                let linkPreview = try OWSLinkPreview.buildValidatedLinkPreview(fromInfo: linkPreviewDraft,
                                                                               transaction: transaction)
                unpreparedMessage.update(with: linkPreview, transaction: transaction)
            } catch {
                Logger.error("error: \(error)")
            }
        }
    }

    @objc
    public var canBePreparedWithoutTransaction: Bool {
        assert(!didCompletePrep)

        guard unsavedAttachmentInfos.isEmpty else {
            return false
        }

        return !OutgoingMessagePreparerHelper.doesMessageNeedsToBePrepared(message)
    }

    @objc
    public func prepareMessageWithoutTransaction() -> TSOutgoingMessage {
        assert(!didCompletePrep)
        assert(canBePreparedWithoutTransaction)

        self.savedAttachmentIds = []
        didCompletePrep = true
        return message
    }

    // NOTE: Any changes to this method should be reflected in canBePreparedWithoutTransaction.
    @objc
    public func prepareMessage(transaction: SDSAnyWriteTransaction) throws -> TSOutgoingMessage {
        assert(!didCompletePrep)

        if unsavedAttachmentInfos.count > 0 {
            try OutgoingMessagePreparerHelper.insertAttachments(unsavedAttachmentInfos,
                                                                for: message,
                                                                transaction: transaction)
        }

        self.savedAttachmentIds = OutgoingMessagePreparerHelper.prepareMessage(forSending: message,
                                                                               transaction: transaction)

        didCompletePrep = true
        return message
    }
}

@objc
public extension TSOutgoingMessage {
    var asPreparer: OutgoingMessagePreparer {
        return OutgoingMessagePreparer(self)
    }
}
