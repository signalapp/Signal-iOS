//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Represents a sync message, being sent from this device, related to "delete
/// for me" actions.
///
/// - SeeAlso ``DeleteForMeOutgoingSyncMessageManager``
@objc(DeleteForMeOutgoingSyncMessage)
class DeleteForMeOutgoingSyncMessage: OWSOutgoingSyncMessage {
    typealias Outgoing = DeleteForMeSyncMessage.Outgoing

    struct Contents: Codable {
        private enum CodingKeys: String, CodingKey {
            case messageDeletes
            case attachmentDeletes
            case conversationDeletes
            case localOnlyConversationDelete
        }

        let messageDeletes: [Outgoing.MessageDeletes]
        /// Attachment deletes were added after this type may already have been
        /// persisted, so this needs to be an optional property that decodes as
        /// `nil` from existing data.
        let attachmentDeletes: [Outgoing.AttachmentDelete]?
        let conversationDeletes: [Outgoing.ConversationDelete]
        let localOnlyConversationDelete: [Outgoing.LocalOnlyConversationDelete]

        #if TESTABLE_BUILD
        init(
            messageDeletes: [Outgoing.MessageDeletes],
            nilAttachmentDeletes: Void,
            conversationDeletes: [Outgoing.ConversationDelete],
            localOnlyConversationDelete: [Outgoing.LocalOnlyConversationDelete]
        ) {
            self.messageDeletes = messageDeletes
            self.attachmentDeletes = nil
            self.conversationDeletes = conversationDeletes
            self.localOnlyConversationDelete = localOnlyConversationDelete
        }
        #endif

        init(
            messageDeletes: [Outgoing.MessageDeletes],
            attachmentDeletes: [Outgoing.AttachmentDelete],
            conversationDeletes: [Outgoing.ConversationDelete],
            localOnlyConversationDelete: [Outgoing.LocalOnlyConversationDelete]
        ) {
            self.attachmentDeletes = attachmentDeletes
            self.messageDeletes = messageDeletes
            self.conversationDeletes = conversationDeletes
            self.localOnlyConversationDelete = localOnlyConversationDelete
        }

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMe {
            let protoBuilder = SSKProtoSyncMessageDeleteForMe.builder()
            protoBuilder.setMessageDeletes(messageDeletes.map { $0.asProto })
            if let attachmentDeletes = attachmentDeletes {
                protoBuilder.setAttachmentDeletes(attachmentDeletes.map { $0.asProto })
            }
            protoBuilder.setConversationDeletes(conversationDeletes.map { $0.asProto })
            protoBuilder.setLocalOnlyConversationDeletes(localOnlyConversationDelete.map { $0.asProto })
            return protoBuilder.buildInfallibly()
        }
    }

    /// A JSON-serialized ``Contents`` struct.
    ///
    /// - Important: The ObjC name must not change, for Mantle compatibility.
    /// - Note
    /// Nullability is intentional, since Mantle will set this property via its
    /// reflection-based `init(coder:)` when we call `super.init(coder:)`.
    @objc(contents)
    private(set) var contentsData: Data!

    init?(
        contents: Contents,
        thread: TSThread,
        tx: SDSAnyReadTransaction
    ) {
        do {
            self.contentsData = try JSONEncoder().encode(contents)
        } catch {
            owsFailDebug("Failed to encode sync message contents!")
            return nil
        }

        super.init(thread: thread, transaction: tx)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    override public var isUrgent: Bool { false }

    override public func syncMessageBuilder(transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let contents: Contents
        do {
            contents = try JSONDecoder().decode(Contents.self, from: contentsData)
        } catch let error {
            owsFailDebug("Failed to decode serialized sync message contents! \(error)")
            return nil
        }

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setDeleteForMe(contents.asProto)
        return syncMessageBuilder
    }
}

// MARK: -

extension DeleteForMeSyncMessage.Outgoing {
    enum ConversationIdentifier: Codable, Equatable {
        case threadServiceId(serviceId: String)
        case threadE164(e164: String)
        case threadGroupId(groupId: Data)

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMeConversationIdentifier {
            let protoBuilder = SSKProtoSyncMessageDeleteForMeConversationIdentifier.builder()
            switch self {
            case .threadServiceId(let serviceId): protoBuilder.setThreadServiceID(serviceId)
            case .threadE164(let e164): protoBuilder.setThreadE164(e164)
            case .threadGroupId(let groupId): protoBuilder.setThreadGroupID(groupId)
            }
            return protoBuilder.buildInfallibly()
        }
    }

    struct AddressableMessage: Codable, Equatable {
        enum Author: Codable, Equatable {
            /// The author's ACI. Note that the author of a message must be an
            /// ACI, never a PNI.
            case aci(aci: String)
            /// The author's E164, if their ACI is absent. This should only be
            /// relevant for old (pre-ACI) messages.
            case e164(e164: String)
        }

        let author: Author
        let sentTimestamp: UInt64

        private init(author: Author, sentTimestamp: UInt64) {
            self.author = author
            self.sentTimestamp = sentTimestamp
        }

        #if TESTABLE_BUILD
        static func forTests(author: Author, sentTimestamp: UInt64) -> AddressableMessage {
            return AddressableMessage(author: author, sentTimestamp: sentTimestamp)
        }
        #endif

        static func addressing(
            message: TSMessage,
            localIdentifiers: LocalIdentifiers
        ) -> AddressableMessage? {
            if let incomingMessage = message as? TSIncomingMessage {
                return AddressableMessage(incomingMessage: incomingMessage)
            } else if let outgoingMessage = message as? TSOutgoingMessage {
                return AddressableMessage(
                    outgoingMessage: outgoingMessage,
                    localIdentifiers: localIdentifiers
                )
            }

            return nil
        }

        private init?(incomingMessage: TSIncomingMessage) {
            if let authorAci = incomingMessage.authorAddress.aci {
                author = .aci(aci: authorAci.serviceIdUppercaseString)
            } else if let authorE164 = incomingMessage.authorAddress.e164 {
                author = .e164(e164: authorE164.stringValue)
            } else {
                return nil
            }

            sentTimestamp = incomingMessage.timestamp
        }

        private init(outgoingMessage: TSOutgoingMessage, localIdentifiers: LocalIdentifiers) {
            author = .aci(aci: localIdentifiers.aci.serviceIdUppercaseString)
            sentTimestamp = outgoingMessage.timestamp
        }

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMeAddressableMessage {
            let protoBuilder = SSKProtoSyncMessageDeleteForMeAddressableMessage.builder()
            protoBuilder.setSentTimestamp(sentTimestamp)
            switch author {
            case .aci(let aci): protoBuilder.setAuthorServiceID(aci)
            case .e164(let e164): protoBuilder.setAuthorE164(e164)
            }
            return protoBuilder.buildInfallibly()
        }
    }

    struct MessageDeletes: Codable, Equatable {
        let conversationIdentifier: ConversationIdentifier
        let addressableMessages: [AddressableMessage]

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMeMessageDeletes {
            let protoBuilder = SSKProtoSyncMessageDeleteForMeMessageDeletes.builder()
            protoBuilder.setConversation(conversationIdentifier.asProto)
            protoBuilder.setMessages(addressableMessages.map { $0.asProto })
            return protoBuilder.buildInfallibly()
        }
    }

    struct AttachmentDelete: Codable, Equatable {
        let conversationIdentifier: ConversationIdentifier
        let targetMessage: AddressableMessage
        let clientUuid: UUID?
        let encryptedDigest: Data?
        let plaintextHash: Data?

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMeAttachmentDelete {
            let protoBuilder = SSKProtoSyncMessageDeleteForMeAttachmentDelete.builder()
            protoBuilder.setConversation(conversationIdentifier.asProto)
            protoBuilder.setTargetMessage(targetMessage.asProto)
            if let clientUuid {
                protoBuilder.setClientUuid(clientUuid.data)
            }
            if let encryptedDigest {
                protoBuilder.setFallbackDigest(encryptedDigest)
            }
            if let plaintextHash {
                protoBuilder.setFallbackPlaintextHash(plaintextHash)
            }
            return protoBuilder.buildInfallibly()
        }
    }

    struct ConversationDelete: Codable, Equatable {
        private enum CodingKeys: String, CodingKey {
            case conversationIdentifier
            case mostRecentAddressableMessages
            case mostRecentNonExpiringAddressableMessages
            case isFullDelete
        }

        let conversationIdentifier: ConversationIdentifier
        let mostRecentAddressableMessages: [AddressableMessage]
        /// Non-expiring messages were added after this type may already have
        /// been persisted, so this needs to be an optional property that
        /// decodes as `nil` from existing data.
        let mostRecentNonExpiringAddressableMessages: [AddressableMessage]?
        let isFullDelete: Bool

        #if TESTABLE_BUILD
        init(
            conversationIdentifier: ConversationIdentifier,
            mostRecentAddressableMessages: [AddressableMessage],
            nilNonExpiringAddressableMessages: Void,
            isFullDelete: Bool
        ) {
            self.conversationIdentifier = conversationIdentifier
            self.mostRecentAddressableMessages = mostRecentAddressableMessages
            self.mostRecentNonExpiringAddressableMessages = nil
            self.isFullDelete = isFullDelete
        }
        #endif

        init(
            conversationIdentifier: ConversationIdentifier,
            mostRecentAddressableMessages: [AddressableMessage],
            mostRecentNonExpiringAddressableMessages: [AddressableMessage],
            isFullDelete: Bool
        ) {
            self.conversationIdentifier = conversationIdentifier
            self.mostRecentAddressableMessages = mostRecentAddressableMessages
            self.mostRecentNonExpiringAddressableMessages = mostRecentNonExpiringAddressableMessages
            self.isFullDelete = isFullDelete
        }

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMeConversationDelete {
            let protoBuilder = SSKProtoSyncMessageDeleteForMeConversationDelete.builder()
            protoBuilder.setConversation(conversationIdentifier.asProto)
            protoBuilder.setMostRecentMessages(mostRecentAddressableMessages.map { $0.asProto })
            if let mostRecentNonExpiringAddressableMessages {
                protoBuilder.setMostRecentNonExpiringMessages(mostRecentNonExpiringAddressableMessages.map { $0.asProto })
            }
            protoBuilder.setIsFullDelete(isFullDelete)
            return protoBuilder.buildInfallibly()
        }
    }

    struct LocalOnlyConversationDelete: Codable, Equatable {
        let conversationIdentifier: ConversationIdentifier

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMeLocalOnlyConversationDelete {
            let protoBuilder = SSKProtoSyncMessageDeleteForMeLocalOnlyConversationDelete.builder()
            protoBuilder.setConversation(conversationIdentifier.asProto)
            return protoBuilder.buildInfallibly()
        }
    }
}
