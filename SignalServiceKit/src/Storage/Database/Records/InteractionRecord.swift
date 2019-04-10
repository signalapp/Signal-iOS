//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

// This Temporary Model Adapter will likely be replaced by the more thourough deserialization
// logic @cmchen is working on. For now we have a crude minimal way of deserializing the necessary
// information to get a migration scaffolded and message windowing working for GRDB.

public enum InteractionRecordType: Int {
    case unknown
    case incomingMessage
    case outgoingMessage
    case info
}

public extension InteractionRecordType {
    init(owsInteractionType: OWSInteractionType) {
        switch owsInteractionType {
        case .unknown:
            fatalError("TODO:")
        case .incomingMessage:
            self = .incomingMessage
        case .outgoingMessage:
            self = .outgoingMessage
        case .error:
            fatalError("TODO:")
        case .call:
            fatalError("TODO:")
        case .info:
            self = .info
        case .offer:
            fatalError("TODO:")
        case .typingIndicator:
            fatalError("TODO:")
        @unknown default:
            fatalError("TODO:")
        }
    }
}

extension InteractionRecordType: Codable { }
extension InteractionRecordType: DatabaseValueConvertible { }

public struct InteractionRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName: String = "interactions"

    public let id: Int
    public let uniqueId: String
    public let threadUniqueId: String
    public let senderTimestamp: UInt64
    public let interactionType: InteractionRecordType
    public let messageBody: String?

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id, uniqueId, threadUniqueId, senderTimestamp, interactionType, messageBody
    }

    public static func columnName(_ column: InteractionRecord.CodingKeys) -> String {
        return column.rawValue
    }
}

public extension TSInteraction {
    class func fromRecord(_ interactionRecord: InteractionRecord, thread: TSThread) -> TSInteraction {
        let interaction: TSInteraction
        switch interactionRecord.interactionType {
        case .unknown:
            fatalError("TODO")
        case .incomingMessage:
            interaction = TSIncomingMessage(incomingMessageWithTimestamp: interactionRecord.senderTimestamp,
                                            in: thread,
                                            authorId: "+555555555", // TODO
                sourceDeviceId: 1, // TODO
                messageBody: interactionRecord.messageBody,
                attachmentIds: [], // TODO
                expiresInSeconds: 0, // TODO
                quotedMessage: nil, // TODO
                contactShare: nil, // TODO
                linkPreview: nil, // TODO
                serverTimestamp: nil, // TODO
                wasReceivedByUD: false) // TODO
        case .outgoingMessage:
            interaction = TSOutgoingMessage(outgoingMessageWithTimestamp: interactionRecord.senderTimestamp,
                                            in: thread,
                                            messageBody: interactionRecord.messageBody,
                                            attachmentIds: [], // TODO
                expiresInSeconds: 0, // TODO
                expireStartedAt: 0, // TODO
                isVoiceMessage: false, // TODO
                groupMetaMessage: .unspecified, // TODO
                quotedMessage: nil, // TODO
                contactShare: nil, // TODO
                linkPreview: nil) // TODO
        case .info:
            // TODO support all types of INFO messages
            interaction = TSInfoMessage(timestamp: interactionRecord.senderTimestamp,
                                        in: thread,
                                        messageType: .typeGroupUpdate) // TODO
        }

        interaction.uniqueId = interactionRecord.uniqueId
        return interaction
    }
}
