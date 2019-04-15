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

extension RPRecentCallType: Codable { }
extension RPRecentCallType: DatabaseValueConvertible { }

extension TSGroupMetaMessage: Codable { }
extension TSGroupMetaMessage: DatabaseValueConvertible { }

extension TSInfoMessageType: Codable { }
extension TSInfoMessageType: DatabaseValueConvertible { }

extension TSOutgoingMessageState: Codable { }
extension TSOutgoingMessageState: DatabaseValueConvertible { }

extension OWSVerificationState: Codable { }
extension OWSVerificationState: DatabaseValueConvertible { }

extension TSErrorMessageType: Codable { }
extension TSErrorMessageType: DatabaseValueConvertible { }

public struct InteractionRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName: String = TSInteractionSerializer.table.tableName

    public let id: Int

    // This defines all of the columns used in the table
    // where this model (and any subclasses) are persisted.
    public let recordType: SDSRecordType
    public let uniqueId: String

    // Base class properties
    public let receivedAtTimestamp: UInt64
    public let sortId: UInt64
    public let timestamp: UInt64
    public let threadUniqueId: String

    // Subclass properties
    public let attachmentFilenameMap: Data?
    public let attachmentIds: Data?
    public let authorId: String?
    // MJK FIXME: should this really be stored?
    public let beforeInteractionId: String?
    public let body: String?
    // MJK TODO signed? unsigned?
    // MJK - I think this property won't be required with GRDB
    public let callSchemaVersion: UInt?
    public let callType: RPRecentCallType?
    // MJK TODO: Signed? optional?
    public let configurationDurationSeconds: UInt32?
    public let configurationIsEnabled: Bool?
    public let contactShare: Data?
    public let createdByRemoteName: String?
    public let createdInExistingGroup: Bool?
    public let customMessage: String?
    // MJK - I think this property won't be required with GRDB
    // MJK TODO Signed?
    public let errorMessageSchemaVersion: UInt?
    // MJK TODO Signed? Size?
    public let errorType: TSErrorMessageType?
    public let expireStartedAt: UInt64?
    public let expiresAt: UInt64?
    public let expiresInSeconds: UInt32?
    public let groupMetaMessage: TSGroupMetaMessage?
    // MJK unstored? Bool?
    public let hasAddToContactsOffer: Bool?
    // MJK unstored? Bool?
    public let hasAddToProfileWhitelistOffer: Bool?
    // MJK unstored? Bool?
    public let hasBlockOffer: Bool?
    // MJK unstored? Bool?
    public let hasLegacyMessageState: Bool?
    public let hasSyncedTranscript: Bool?
    // MJK - I think this property won't be required with GRDB
    public let infoMessageSchemaVersion: UInt?
    public let isFromLinkedDevice: Bool?
    public let isLocalChange: Bool?
    public let isVoiceMessage: Bool?
    // MJK - I think this property won't be required with GRDB
    public let legacyMessageState: TSOutgoingMessageState?
    // MJK - I think this property won't be required with GRDB
    public let legacyWasDelivered: Bool?
    public let linkPreview: Data?
    // MJK: rename this column to be clear that it's about info messages only
    public let messageType: TSInfoMessageType?
    public let mostRecentFailureText: String?
    public let quotedMessage: Data?
    public let read: Bool?
    public let recipientId: String?
    public let recipientStateMap: Data?
    // MJK - I think this property won't be required with GRDB
    public let schemaVersion: UInt?
    public let serverTimestamp: Int64?
    public let sourceDeviceId: UInt32?
    public let unregisteredRecipientId: String?
    public let verificationState: OWSVerificationState?
    public let wasReceivedByUD: Bool?

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case receivedAtTimestamp
        case sortId
        case timestamp
        case threadUniqueId = "uniqueThreadId"
        case attachmentFilenameMap
        case attachmentIds
        case authorId
        case beforeInteractionId
        case body
        case callSchemaVersion
        case callType
        case configurationDurationSeconds
        case configurationIsEnabled
        case contactShare
        case createdByRemoteName
        case createdInExistingGroup
        case customMessage
        case errorMessageSchemaVersion
        case errorType
        case expireStartedAt
        case expiresAt
        case expiresInSeconds
        case groupMetaMessage
        case hasAddToContactsOffer
        case hasAddToProfileWhitelistOffer
        case hasBlockOffer
        case hasLegacyMessageState
        case hasSyncedTranscript
        case infoMessageSchemaVersion
        case isFromLinkedDevice
        case isLocalChange
        case isVoiceMessage
        case legacyMessageState
        case legacyWasDelivered
        case linkPreview
        case messageType
        case mostRecentFailureText
        case quotedMessage
        case read
        case recipientId
        case recipientStateMap
        case schemaVersion
        case serverTimestamp
        case sourceDeviceId
        case unregisteredRecipientId
        case verificationState
        case wasReceivedByUD
    }

    public static func columnName(_ column: InteractionRecord.CodingKeys) -> String {
        return column.rawValue
    }

    public var decodedAttachmentIds: [String]? {
        guard let encoded = self.attachmentIds else {
            return nil
        }
        return try! SDSDeserializer.unarchive(encoded)
    }

    public var decodedContactShare: OWSContact? {
        guard let encoded = self.contactShare else {
            return nil
        }
        return try! SDSDeserializer.unarchive(encoded)
    }

    public var decodedLinkPreview: OWSLinkPreview? {
        guard let encoded = self.linkPreview else {
            return nil
        }
        return try! SDSDeserializer.unarchive(encoded)
    }

    public var decodedQuotedMessage: TSQuotedMessage? {
        guard let encoded = self.quotedMessage else {
            return nil
        }
        return try! SDSDeserializer.unarchive(encoded)
    }

    public var decodedAttachmentFilenameMap: [String: String]? {
        guard let encoded = self.attachmentFilenameMap else {
            return nil
        }
        return try! SDSDeserializer.unarchive(encoded)
    }

    public var decodedRecipientStateMap: [String: TSOutgoingMessageRecipientState]? {
        guard let encoded = self.recipientStateMap else {
            return nil
        }
        return try! SDSDeserializer.unarchive(encoded)
    }
}

public extension TSInteraction {
    class func fromRecord(_ record: InteractionRecord) -> TSInteraction {
        let interaction: TSInteraction
        switch record.recordType {
        case .addToContactsOfferMessage:
            fatalError("wrong record type")
        case .addToProfileWhitelistOfferMessage:
            fatalError("wrong record type")
        case .attachmentInfo:
            fatalError("wrong record type")
        case .batchMessageProcessor:
            fatalError("wrong record type")
        case .blockingManager:
            fatalError("wrong record type")
        case .contact:
            fatalError("wrong record type")
        case .contactAddress:
            fatalError("wrong record type")
        case .contactEmail:
            fatalError("wrong record type")
        case .contactName:
            fatalError("wrong record type")
        case .contactOffersInteraction:
            return OWSContactOffersInteraction(uniqueId: record.uniqueId,
                                               receivedAtTimestamp: record.receivedAtTimestamp,
                                               sortId: record.sortId,
                                               timestamp: record.timestamp,
                                               uniqueThreadId: record.threadUniqueId,
                                               beforeInteractionId: record.beforeInteractionId!,
                                               hasAddToContactsOffer: record.hasAddToContactsOffer!,
                                               hasAddToProfileWhitelistOffer: record.hasAddToProfileWhitelistOffer!,
                                               hasBlockOffer: record.hasBlockOffer!,
                                               recipientId: record.recipientId!)
        case .contactPhoneNumber:
            fatalError("wrong record type")
        case .contacts:
            fatalError("wrong record type")
        case .disappearingConfigurationUpdateInfoMessage:
            return OWSDisappearingConfigurationUpdateInfoMessage(uniqueId: record.uniqueId,
                                                                 receivedAtTimestamp: record.receivedAtTimestamp,
                                                                 sortId: record.sortId,
                                                                 timestamp: record.timestamp,
                                                                 uniqueThreadId: record.threadUniqueId,
                                                                 attachmentIds: record.decodedAttachmentIds!,
                                                                 body: record.body,
                                                                 contactShare: record.decodedContactShare,
                                                                 expireStartedAt: record.expireStartedAt!,
                                                                 expiresAt: record.expiresAt!,
                                                                 expiresInSeconds: record.expiresInSeconds!,
                                                                 linkPreview: record.decodedLinkPreview,
                                                                 quotedMessage: record.decodedQuotedMessage,
                                                                 schemaVersion: record.schemaVersion!,
                                                                 customMessage: record.customMessage,
                                                                 infoMessageSchemaVersion: record.infoMessageSchemaVersion!,
                                                                 messageType: record.messageType!,
                                                                 read: record.read!,
                                                                 unregisteredRecipientId: record.unregisteredRecipientId,
                                                                 configurationDurationSeconds: record.configurationDurationSeconds!,
                                                                 configurationIsEnabled: record.configurationIsEnabled!,
                                                                 createdByRemoteName: record.createdByRemoteName,
                                                                 createdInExistingGroup: record.createdInExistingGroup!)
        case .disappearingMessagesConfigurationMessage:
            return OWSDisappearingMessagesConfigurationMessage(uniqueId: record.uniqueId,
                                                               receivedAtTimestamp: record.receivedAtTimestamp,
                                                               sortId: record.sortId,
                                                               timestamp: record.timestamp,
                                                               uniqueThreadId: record.threadUniqueId,
                                                               attachmentIds: record.decodedAttachmentIds!,
                                                               body: record.body,
                                                               contactShare: record.decodedContactShare,
                                                               expireStartedAt: record.expireStartedAt!,
                                                               expiresAt: record.expiresAt!,
                                                               expiresInSeconds: record.expiresInSeconds!,
                                                               linkPreview: record.decodedLinkPreview,
                                                               quotedMessage: record.decodedQuotedMessage,
                                                               schemaVersion: record.schemaVersion!,
                                                               attachmentFilenameMap: record.decodedAttachmentFilenameMap!,
                                                               customMessage: record.customMessage!,
                                                               groupMetaMessage: record.groupMetaMessage!,
                                                               hasLegacyMessageState: record.hasLegacyMessageState!,
                                                               hasSyncedTranscript: record.hasSyncedTranscript!,
                                                               isFromLinkedDevice: record.isFromLinkedDevice!,
                                                               isVoiceMessage: record.isVoiceMessage!,
                                                               legacyMessageState: record.legacyMessageState!,
                                                               legacyWasDelivered: record.legacyWasDelivered!,
                                                               mostRecentFailureText: record.mostRecentFailureText,
                                                               recipientStateMap: record.decodedRecipientStateMap)
        case .disappearingMessagesFinder:
            fatalError("wrong record type")
        case .disappearingMessagesJob:
            fatalError("wrong record type")
        case .dynamicOutgoingMessage:
            return OWSDynamicOutgoingMessage(uniqueId: record.uniqueId,
                                             receivedAtTimestamp: record.receivedAtTimestamp,
                                             sortId: record.sortId,
                                             timestamp: record.timestamp,
                                             uniqueThreadId: record.threadUniqueId,
                                             attachmentIds: record.decodedAttachmentIds!,
                                             body: record.body,
                                             contactShare: record.decodedContactShare,
                                             expireStartedAt: record.expireStartedAt!,
                                             expiresAt: record.expiresAt!,
                                             expiresInSeconds: record.expiresInSeconds!,
                                             linkPreview: record.decodedLinkPreview,
                                             quotedMessage: record.decodedQuotedMessage,
                                             schemaVersion: record.schemaVersion!,
                                             attachmentFilenameMap: record.decodedAttachmentFilenameMap!,
                                             customMessage: record.customMessage,
                                             groupMetaMessage: record.groupMetaMessage!,
                                             hasLegacyMessageState: record.hasLegacyMessageState!,
                                             hasSyncedTranscript: record.hasSyncedTranscript!,
                                             isFromLinkedDevice: record.isFromLinkedDevice!,
                                             isVoiceMessage: record.isVoiceMessage!,
                                             legacyMessageState: record.legacyMessageState!,
                                             legacyWasDelivered: record.legacyWasDelivered!,
                                             mostRecentFailureText: record.mostRecentFailureText,
                                             recipientStateMap: record.decodedRecipientStateMap)
        case .failedAttachmentDownloadsJob:
            fatalError("wrong record type")
        case .failedMessagesJob:
            fatalError("wrong record type")
        case .identityManager:
            fatalError("wrong record type")
        case .incompleteCallsJob:
            fatalError("wrong record type")
        case .messageContentJob:
            fatalError("wrong record type")
        case .messageContentJobFinder:
            fatalError("wrong record type")
        case .messageContentQueue:
            fatalError("wrong record type")
        case .messageDecryptJob:
            fatalError("wrong record type")
        case .messageDecryptJobFinder:
            fatalError("wrong record type")
        case .messageDecryptQueue:
            fatalError("wrong record type")
        case .messageDecryptResult:
            fatalError("wrong record type")
        case .messageDecrypter:
            fatalError("wrong record type")
        case .messageManager:
            fatalError("wrong record type")
        case .messageReceiver:
            fatalError("wrong record type")
        case .messageSender:
            fatalError("wrong record type")
        case .messageServiceParams:
            fatalError("wrong record type")
        case .messageUtils:
            fatalError("wrong record type")
        case .outgoingAttachmentInfo:
            fatalError("wrong record type")
        case .outgoingReceiptManager:
            fatalError("wrong record type")
        case .outgoingSentMessageTranscript:
            fatalError("TODO?")
        case .readReceiptManager:
            fatalError("wrong record type")
        case .sendMessageOperation:
            fatalError("wrong record type")
        case .syncConfigurationMessage:
            fatalError("TODO?")
        case .syncContactsMessage:
            fatalError("TODO?")
        case .syncGroupsRequestMessage:
            fatalError("TODO?")
        case .unknownContactBlockOfferMessage:
            fatalError("TODO?")
        case .verificationStateChangeMessage:
            return OWSVerificationStateChangeMessage(uniqueId: record.uniqueId,
                                                     receivedAtTimestamp: record.receivedAtTimestamp,
                                                     sortId: record.sortId,
                                                     timestamp: record.timestamp,
                                                     uniqueThreadId: record.threadUniqueId,
                                                     attachmentIds: record.decodedAttachmentIds!,
                                                     body: record.body,
                                                     contactShare: record.decodedContactShare,
                                                     expireStartedAt: record.expireStartedAt!,
                                                     expiresAt: record.expiresAt!,
                                                     expiresInSeconds: record.expiresInSeconds!,
                                                     linkPreview: record.decodedLinkPreview,
                                                     quotedMessage: record.decodedQuotedMessage,
                                                     schemaVersion: record.schemaVersion!,
                                                     customMessage: record.customMessage,
                                                     infoMessageSchemaVersion: record.infoMessageSchemaVersion!,
                                                     messageType: record.messageType!,
                                                     read: record.read!,
                                                     unregisteredRecipientId: record.unregisteredRecipientId,
                                                     isLocalChange: record.isLocalChange!,
                                                     recipientId: record.recipientId!,
                                                     verificationState: record.verificationState!)
        case .outgoingMessagePreparer:
            fatalError("wrong record type")
        case .call:
            return TSCall(uniqueId: record.uniqueId,
                          receivedAtTimestamp: record.receivedAtTimestamp,
                          sortId: record.sortId,
                          timestamp: record.timestamp,
                          uniqueThreadId: record.threadUniqueId,
                          callSchemaVersion: record.callSchemaVersion!,
                          callType: record.callType!,
                          read: record.read!)
        case .contactThread:
            fatalError("TODO?")
        case .errorMessage:
            return TSErrorMessage(uniqueId: record.uniqueId,
                                  receivedAtTimestamp: record.receivedAtTimestamp,
                                  sortId: record.sortId,
                                  timestamp: record.timestamp,
                                  uniqueThreadId: record.threadUniqueId,
                                  attachmentIds: record.decodedAttachmentIds!,
                                  body: record.body,
                                  contactShare: record.decodedContactShare,
                                  expireStartedAt: record.expireStartedAt!,
                                  expiresAt: record.expiresAt!,
                                  expiresInSeconds: record.expiresInSeconds!,
                                  linkPreview: record.decodedLinkPreview,
                                  quotedMessage: record.decodedQuotedMessage,
                                  schemaVersion: record.schemaVersion!,
                                  errorMessageSchemaVersion: record.errorMessageSchemaVersion!,
                                  errorType: record.errorType!,
                                  read: record.read!,
                                  recipientId: record.recipientId)
        case .groupModel:
            fatalError("wrong record type")
        case .groupThread:
            fatalError("wrong record type")
        case .incomingMessage:
            return TSIncomingMessage(uniqueId: record.uniqueId,
                                     receivedAtTimestamp: record.receivedAtTimestamp,
                                     sortId: record.sortId,
                                     timestamp: record.timestamp,
                                     uniqueThreadId: record.threadUniqueId,
                                     attachmentIds: record.decodedAttachmentIds!,
                                     body: record.body,
                                     contactShare: record.decodedContactShare,
                                     expireStartedAt: record.expireStartedAt!,
                                     expiresAt: record.expiresAt!,
                                     expiresInSeconds: record.expiresInSeconds!,
                                     linkPreview: record.decodedLinkPreview,
                                     quotedMessage: record.decodedQuotedMessage,
                                     schemaVersion: record.schemaVersion!,
                                     authorId: record.authorId!,
                                     read: record.read!,
                                     serverTimestamp: record.serverTimestamp == nil ? nil : NSNumber(value: record.serverTimestamp!),
                                     sourceDeviceId: record.sourceDeviceId!,
                                     wasReceivedByUD: record.wasReceivedByUD!)
        case .infoMessage:
            return TSInfoMessage(uniqueId: record.uniqueId,
                                 receivedAtTimestamp: record.receivedAtTimestamp,
                                 sortId: record.sortId,
                                 timestamp: record.timestamp,
                                 uniqueThreadId: record.threadUniqueId,
                                 attachmentIds: record.decodedAttachmentIds!,
                                 body: record.body,
                                 contactShare: record.decodedContactShare,
                                 expireStartedAt: record.expireStartedAt!,
                                 expiresAt: record.expiresAt!,
                                 expiresInSeconds: record.expiresInSeconds!,
                                 linkPreview: record.decodedLinkPreview,
                                 quotedMessage: record.decodedQuotedMessage,
                                 schemaVersion: record.schemaVersion!,
                                 customMessage: record.customMessage,
                                 infoMessageSchemaVersion: record.infoMessageSchemaVersion!,
                                 messageType: record.messageType!,
                                 read: record.read!,
                                 unregisteredRecipientId: record.unregisteredRecipientId)
        case .interaction:
            fatalError("abtract class")
        case .message:
            fatalError("abtract class")
            return TSMessage(uniqueId: record.uniqueId,
                             receivedAtTimestamp: record.receivedAtTimestamp,
                             sortId: record.sortId,
                             timestamp: record.timestamp,
                             uniqueThreadId: record.threadUniqueId,
                             attachmentIds: record.decodedAttachmentIds!,
                             body: record.body,
                             contactShare: record.decodedContactShare,
                             expireStartedAt: record.expireStartedAt!,
                             expiresAt: record.expiresAt!,
                             expiresInSeconds: record.expiresInSeconds!,
                             linkPreview: record.decodedLinkPreview,
                             quotedMessage: record.decodedQuotedMessage,
                             schemaVersion: record.schemaVersion!)
        case .outgoingMessage:
            return TSOutgoingMessage(uniqueId: record.uniqueId,
                                     receivedAtTimestamp: record.receivedAtTimestamp,
                                     sortId: record.sortId,
                                     timestamp: record.timestamp,
                                     uniqueThreadId: record.threadUniqueId,
                                     attachmentIds: record.decodedAttachmentIds!,
                                     body: record.body,
                                     contactShare: record.decodedContactShare,
                                     expireStartedAt: record.expireStartedAt!,
                                     expiresAt: record.expiresAt!,
                                     expiresInSeconds: record.expiresInSeconds!,
                                     linkPreview: record.decodedLinkPreview,
                                     quotedMessage: record.decodedQuotedMessage,
                                     schemaVersion: record.schemaVersion!,
                                     attachmentFilenameMap: record.decodedAttachmentFilenameMap!,
                                     customMessage: record.customMessage,
                                     groupMetaMessage: record.groupMetaMessage!,
                                     hasLegacyMessageState: record.hasLegacyMessageState!,
                                     hasSyncedTranscript: record.hasSyncedTranscript!,
                                     isFromLinkedDevice: record.isFromLinkedDevice!,
                                     isVoiceMessage: record.isVoiceMessage!,
                                     legacyMessageState: record.legacyMessageState!,
                                     legacyWasDelivered: record.legacyWasDelivered!,
                                     mostRecentFailureText: record.mostRecentFailureText,
                                     recipientStateMap: record.decodedRecipientStateMap)
        case .outgoingMessageRecipientState:
            fatalError("wrong record type")
        case .quotedMessage:
            fatalError("wrong record type")
        case .recipientReadReceipt:
            fatalError("TODO?")
        case .thread:
            fatalError("wrong record type")
        case .unreadIndicatorInteraction:
            return TSUnreadIndicatorInteraction(uniqueId: record.uniqueId,
                                                receivedAtTimestamp: record.receivedAtTimestamp,
                                                sortId: record.sortId,
                                                timestamp: record.timestamp,
                                                uniqueThreadId: record.threadUniqueId)
        case .yapDatabaseObject:
            fatalError("wrong record type")
        @unknown default:
            fatalError("TODO?")
        }
        return interaction
    }
}
