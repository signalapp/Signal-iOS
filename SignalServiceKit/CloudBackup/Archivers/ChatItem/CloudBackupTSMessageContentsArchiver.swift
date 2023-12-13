//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class CloudBackupTSMessageContentsArchiver: CloudBackupProtoArchiver {

    typealias ChatItemMessageType = CloudBackup.ChatItemMessageType

    // MARK: - Archiving

    func archiveMessageContents(
        _ message: TSMessage,
        tx: DBReadTransaction
    ) -> CloudBackup.ArchiveInteractionResult<ChatItemMessageType> {
        guard let body = message.body else {
            // TODO: handle non simple text messages.
            return .notYetImplemented
        }

        let standardMessageBuilder = BackupProtoStandardMessage.builder()
        let textBuilder = BackupProtoText.builder(body: body)

        var bodyRangeErrors = [CloudBackup.ArchiveInteractionResult<ChatItemMessageType>.Error]()

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
                bodyRangeErrors.append(.init(objectId: message.timestamp, error: .protoSerializationError(error)))
            }
        }
        do {
            let textProto = try textBuilder.build()
            standardMessageBuilder.setText(textProto)
        } catch let error {
            // Count this as a complete and total failure of the message.
            return .messageFailure([.init(objectId: message.timestamp, error: .protoSerializationError(error))])
        }

        // TODO: reactions

        let standardMessageProto: BackupProtoStandardMessage
        do {
            standardMessageProto = try standardMessageBuilder.build()
        } catch let error {
            return .messageFailure([.init(objectId: message.timestamp, error: .protoSerializationError(error))])
        }

        if bodyRangeErrors.isEmpty {
            return .success(.standard(standardMessageProto))
        } else {
            return .partialFailure(.standard(standardMessageProto), bodyRangeErrors)
        }
    }

    // MARK: - Restoring

    func restoreMessageBody(
        _ chatItemType: ChatItemMessageType
    ) -> (MessageBody?, CloudBackup.RestoreFrameResult<Void>) {
        switch chatItemType {
        case .standard(let standardMessage):
            if let text = standardMessage.text {
                return restoreMessageBody(text)
            } else {
                fallthrough
            }
        case .contact, .voice, .sticker, .remotelyDeleted, .chatUpdate:
            return (nil, .success)
        }
    }

    func restoreMessageBody(_ text: BackupProtoText) -> (MessageBody, CloudBackup.RestoreFrameResult<Void>) {
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
            return (body, .success)
        } else {
            // We still get text, albeit without any mentions or styles, if
            // we have these failures. So count as a partial restore, not
            // complete failure.
            return (body, .partialRestore((), partialErrors))
        }
    }
}
