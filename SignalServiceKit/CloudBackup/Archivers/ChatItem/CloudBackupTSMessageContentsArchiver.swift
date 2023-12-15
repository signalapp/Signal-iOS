//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension CloudBackup {

    // TODO: Flesh this out. Not sure how exactly we will map
    // from the "types" in the proto to the "types" in our database.

    /// Represents message content "types" as they are represented in iOS code, after
    /// being mapped from their representation in the backup proto. For example, normal
    /// text messages and quoted replies are a single "type" in the proto, but have separate
    /// class structures in the iOS code.
    /// This object will be passed back into the ``CloudBackupTSMessageContentsArchiver`` class
    /// after the TSMessage has been created, so that downstream objects that require the TSMessage exist
    /// can be created afterwards. So anything needed for that (but not needed to create the TSMessage)
    /// can be made a fileprivate variable in these structs.
    internal enum RestoredMessageContents {
        struct Text {

            // Internal - these fields are exposed for TSMessage construction.

            internal let body: MessageBody

            // Private - these fields are used by ``restoreDownstreamObjects`` to
            //     construct objects that are parsed from the backup proto but require
            //     the TSMessage to exist first before they can be created/inserted.

            fileprivate let reactions: [BackupProtoReaction]
        }

        case text(Text)
    }
}

extension CloudBackup.RestoredMessageContents {

    var body: MessageBody? {
        switch self {
        case .text(let text):
            return text.body
        }
    }
}

internal class CloudBackupTSMessageContentsArchiver: CloudBackupProtoArchiver {

    typealias ChatItemMessageType = CloudBackup.ChatItemMessageType

    private let reactionArchiver: CloudBackupReactionArchiver

    init(reactionArchiver: CloudBackupReactionArchiver) {
        self.reactionArchiver = reactionArchiver
    }

    // MARK: - Archiving

    func archiveMessageContents(
        _ message: TSMessage,
        context: CloudBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> CloudBackup.ArchiveInteractionResult<ChatItemMessageType> {
        guard let body = message.body else {
            // TODO: handle non simple text messages.
            return .notYetImplemented
        }

        let standardMessageBuilder = BackupProtoStandardMessage.builder()
        let textBuilder = BackupProtoText.builder(body: body)

        var partialErrors = [CloudBackup.ArchiveInteractionResult<ChatItemMessageType>.Error]()

        for bodyRange in message.bodyRanges?.toProtoBodyRanges() ?? [] {
            let bodyRangeProtoBuilder = BackupProtoBodyRange.builder()
            bodyRangeProtoBuilder.setStart(bodyRange.start)
            bodyRangeProtoBuilder.setLength(bodyRange.length)
            if
                let rawMentionAci = bodyRange.mentionAci,
                let mentionUuid = UUID(uuidString: rawMentionAci)
            {
                bodyRangeProtoBuilder.setMentionAci(Aci(fromUUID: mentionUuid).serviceIdBinary.asData)
            } else if let style = bodyRange.style {
                switch style {
                case .none:
                    bodyRangeProtoBuilder.setStyle(.none)
                case .bold:
                    bodyRangeProtoBuilder.setStyle(.bold)
                case .italic:
                    bodyRangeProtoBuilder.setStyle(.italic)
                case .spoiler:
                    bodyRangeProtoBuilder.setStyle(.spoiler)
                case .strikethrough:
                    bodyRangeProtoBuilder.setStyle(.strikethrough)
                case .monospace:
                    bodyRangeProtoBuilder.setStyle(.monospace)
                }
            }
            do {
                let bodyRangeProto = try bodyRangeProtoBuilder.build()
                textBuilder.addBodyRanges(bodyRangeProto)
            } catch let error {
                // TODO: should these failures fail the whole message?
                // For now, just ignore the one body range and keep going.
                partialErrors.append(.init(objectId: message.chatItemId, error: .protoSerializationError(error)))
            }
        }
        do {
            let textProto = try textBuilder.build()
            standardMessageBuilder.setText(textProto)
        } catch let error {
            // Count this as a complete and total failure of the message.
            return .messageFailure([.init(objectId: message.chatItemId, error: .protoSerializationError(error))])
        }

        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context,
            tx: tx
        )

        let reactions: [BackupProtoReaction]
        switch reactionsResult {
        case .success(let values):
            reactions = values
        case .isPastRevision:
            return .isPastRevision
        case .notYetImplemented:
            return .notYetImplemented
        case .partialFailure(let values, let errors):
            partialErrors.append(contentsOf: errors)
            reactions = values
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .messageFailure(partialErrors)
        case .completeFailure(let error):
            return .completeFailure(error)
        }
        standardMessageBuilder.setReactions(reactions)

        let standardMessageProto: BackupProtoStandardMessage
        do {
            standardMessageProto = try standardMessageBuilder.build()
        } catch let error {
            return .messageFailure([.init(objectId: message.chatItemId, error: .protoSerializationError(error))])
        }

        if partialErrors.isEmpty {
            return .success(.standard(standardMessageProto))
        } else {
            return .partialFailure(.standard(standardMessageProto), partialErrors)
        }
    }

    // MARK: - Restoring

    typealias RestoreResult = CloudBackup.RestoreInteractionResult<CloudBackup.RestoredMessageContents>

    /// Parses the contents of ``CloudBackup.ChatItemMessageType`` (which represents the proto structure of message contents)
    /// into ``CloudBackup.RestoredMessageContents``, which maps more directly to the ``TSMessage`` values in our database.
    ///
    /// Does NOT create the ``TSMessage``; callers are expected to utilize the restored contents to construct and insert the message.
    ///
    /// Callers MUST call ``restoreDownstreamObjects`` after creating and inserting the ``TSMessage``.
    func restoreContents(
        _ chatItemType: ChatItemMessageType,
        tx: DBWriteTransaction
    ) -> RestoreResult {
        switch chatItemType {
        case .standard(let standardMessage):
            return restoreStandardMessage(standardMessage)
        case .contact, .voice, .sticker, .remotelyDeleted, .chatUpdate:
            // Other types not supported yet.
            return .messageFailure([.unimplemented])
        }
    }

    /// After a caller creates a ``TSMessage`` from the results of ``restoreContents``, they MUST call this method
    /// to create and insert all "downstream" objects: those that reference the ``TSMessage`` and require it for their own creation.
    ///
    /// This method will create and insert all necessary objects (e.g. reactions).
    func restoreDownstreamObjects(
        message: TSMessage,
        restoredContents: CloudBackup.RestoredMessageContents,
        context: CloudBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> CloudBackup.RestoreInteractionResult<Void> {
        let restoreReactionsResult: CloudBackup.RestoreInteractionResult<Void>
        switch restoredContents {
        case .text(let text):
            restoreReactionsResult = reactionArchiver.restoreReactions(
                text.reactions,
                message: message,
                context: context.recipientContext,
                tx: tx
            )
        }

        return restoreReactionsResult
    }

    // MARK: Helpers

    private func restoreStandardMessage(
        _ standardMessage: BackupProtoStandardMessage
    ) -> RestoreResult {
        guard let text = standardMessage.text else {
            // Non-text not supported yet.
            return .messageFailure([.unimplemented])
        }

        let messageBodyResult = restoreMessageBody(text)
        switch messageBodyResult {
        case .success(let body):
            return .success(.text(.init(body: body, reactions: standardMessage.reactions)))
        case .partialRestore(let body, let partialErrors):
            return .partialRestore(.text(.init(body: body, reactions: standardMessage.reactions)), partialErrors)
        case .messageFailure(let errors):
            return .messageFailure(errors)
        }
    }

    func restoreMessageBody(_ text: BackupProtoText) -> CloudBackup.RestoreInteractionResult<MessageBody> {
        var partialErrors = [CloudBackup.RestoringFrameError]()
        var bodyMentions = [NSRange: Aci]()
        var bodyStyles = [NSRangedValue<MessageBodyRanges.SingleStyle>]()
        for bodyRange in text.bodyRanges {
            let range = NSRange(location: Int(bodyRange.start), length: Int(bodyRange.length))
            if let rawMentionAci = bodyRange.mentionAci {
                guard let mentionAci = try? Aci.parseFrom(serviceIdBinary: rawMentionAci) else {
                    partialErrors.append(.invalidProtoData)
                    continue
                }
                bodyMentions[range] = mentionAci
            } else if bodyRange.hasStyle {
                let swiftStyle: MessageBodyRanges.SingleStyle
                switch bodyRange.style {
                case .some(.none):
                    // Unrecognized enum value
                    partialErrors.append(.unknownFrameType)
                    continue
                case nil:
                    // Missing enum value
                    partialErrors.append(.invalidProtoData)
                    continue
                case .bold:
                    swiftStyle = .bold
                case .italic:
                    swiftStyle = .italic
                case .monospace:
                    swiftStyle = .monospace
                case .spoiler:
                    swiftStyle = .spoiler
                case .strikethrough:
                    swiftStyle = .strikethrough
                }
                bodyStyles.append(.init(swiftStyle, range: range))
            }
        }
        let bodyRanges = MessageBodyRanges(mentions: bodyMentions, styles: bodyStyles)
        let body = MessageBody(text: text.body, ranges: bodyRanges)
        if partialErrors.isEmpty {
            return .success(body)
        } else {
            // We still get text, albeit without any mentions or styles, if
            // we have these failures. So count as a partial restore, not
            // complete failure.
            return .partialRestore(body, partialErrors)
        }
    }
}
