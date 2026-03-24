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
final class DeleteForMeOutgoingSyncMessage: OutgoingSyncMessage {
    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        guard let contents = coder.decodeObject(of: NSData.self, forKey: "contents") as Data? else {
            return nil
        }
        self.contents = contents
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(contents, forKey: "contents")
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(contents)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.contents == object.contents else { return false }
        return true
    }

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
            localOnlyConversationDelete: [Outgoing.LocalOnlyConversationDelete],
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
            localOnlyConversationDelete: [Outgoing.LocalOnlyConversationDelete],
        ) {
            self.attachmentDeletes = attachmentDeletes
            self.messageDeletes = messageDeletes
            self.conversationDeletes = conversationDeletes
            self.localOnlyConversationDelete = localOnlyConversationDelete
        }

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMe {
            let protoBuilder = SSKProtoSyncMessageDeleteForMe.builder()
            protoBuilder.setMessageDeletes(messageDeletes.map { $0.asProto })
            if let attachmentDeletes {
                protoBuilder.setAttachmentDeletes(attachmentDeletes.map { $0.asProto })
            }
            protoBuilder.setConversationDeletes(conversationDeletes.map { $0.asProto })
            protoBuilder.setLocalOnlyConversationDeletes(localOnlyConversationDelete.map { $0.asProto })
            return protoBuilder.buildInfallibly()
        }
    }

    /// A JSON-serialized ``Contents`` struct.
    private(set) var contents: Data

    init?(
        contents: Contents,
        localThread: TSContactThread,
        tx: DBReadTransaction,
    ) {
        do {
            self.contents = try JSONEncoder().encode(contents)
        } catch {
            owsFailDebug("Failed to encode sync message contents!")
            return nil
        }

        super.init(localThread: localThread, tx: tx)
    }

    override var isUrgent: Bool { false }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let contents: Contents
        do {
            contents = try JSONDecoder().decode(Contents.self, from: self.contents)
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

    enum CodableConversationIdentifier: Codable, Equatable {
        case threadServiceId(serviceId: ServiceIdUppercaseString<ServiceId>)
        case threadE164(e164: String)
        case threadGroupId(groupId: Data)

        init(_ conversationIdentifier: ConversationIdentifier) {
            switch conversationIdentifier {
            case .serviceId(let serviceId):
                self = .threadServiceId(serviceId: ServiceIdUppercaseString(wrappedValue: serviceId))
            case .e164(let e164):
                self = .threadE164(e164: e164.stringValue)
            case .groupIdentifier(let groupIdentifier):
                self = .threadGroupId(groupId: groupIdentifier.serialize())
            }
        }

        var asProto: SSKProtoConversationIdentifier {
            let protoBuilder = SSKProtoConversationIdentifier.builder()
            switch self {
            case .threadServiceId(let serviceId):
                protoBuilder.setThreadServiceIDBinary(serviceId.wrappedValue.serviceIdBinary)
            case .threadE164(let e164): protoBuilder.setThreadE164(e164)
            case .threadGroupId(let groupId): protoBuilder.setThreadGroupID(groupId)
            }
            return protoBuilder.buildInfallibly()
        }
    }

    struct CodableAddressableMessage: Codable, Equatable {
        enum Author: Codable, Equatable {
            case aci(aci: ServiceIdUppercaseString<Aci>)
            case e164(e164: String)
        }

        let author: Author
        let sentTimestamp: UInt64

        init(_ addressableMessage: AddressableMessage) {
            switch addressableMessage.author {
            case .aci(let aci):
                author = .aci(aci: ServiceIdUppercaseString(wrappedValue: aci))
            case .e164(let e164):
                author = .e164(e164: e164.stringValue)
            }
            sentTimestamp = addressableMessage.sentTimestamp
        }

        var asProto: SSKProtoAddressableMessage {
            let protoBuilder = SSKProtoAddressableMessage.builder()
            protoBuilder.setSentTimestamp(sentTimestamp)
            switch author {
            case .aci(let aci):
                protoBuilder.setAuthorServiceIDBinary(aci.wrappedValue.serviceIdBinary)
            case .e164(let e164): protoBuilder.setAuthorE164(e164)
            }
            return protoBuilder.buildInfallibly()
        }
    }

    struct MessageDeletes: Codable, Equatable {
        let conversationIdentifier: CodableConversationIdentifier
        let addressableMessages: [CodableAddressableMessage]

        init(
            conversationIdentifier: ConversationIdentifier,
            addressableMessages: [AddressableMessage],
        ) {
            self.conversationIdentifier = CodableConversationIdentifier(conversationIdentifier)
            self.addressableMessages = addressableMessages.map { CodableAddressableMessage($0) }
        }

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMeMessageDeletes {
            let protoBuilder = SSKProtoSyncMessageDeleteForMeMessageDeletes.builder()
            protoBuilder.setConversation(conversationIdentifier.asProto)
            protoBuilder.setMessages(addressableMessages.map { $0.asProto })
            return protoBuilder.buildInfallibly()
        }
    }

    struct AttachmentDelete: Codable, Equatable {
        let conversationIdentifier: CodableConversationIdentifier
        let targetMessage: CodableAddressableMessage
        let clientUuid: UUID?
        let encryptedDigest: Data?
        let plaintextHash: Data?

        init(
            conversationIdentifier: ConversationIdentifier,
            targetMessage: AddressableMessage,
            clientUuid: UUID?,
            encryptedDigest: Data?,
            plaintextHash: Data?,
        ) {
            self.conversationIdentifier = CodableConversationIdentifier(conversationIdentifier)
            self.targetMessage = CodableAddressableMessage(targetMessage)
            self.clientUuid = clientUuid
            self.encryptedDigest = encryptedDigest
            self.plaintextHash = plaintextHash
        }

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

        let conversationIdentifier: CodableConversationIdentifier
        let mostRecentAddressableMessages: [CodableAddressableMessage]
        /// Non-expiring messages were added after this type may already have
        /// been persisted, so this needs to be an optional property that
        /// decodes as `nil` from existing data.
        let mostRecentNonExpiringAddressableMessages: [CodableAddressableMessage]?
        let isFullDelete: Bool

#if TESTABLE_BUILD
        init(
            conversationIdentifier: ConversationIdentifier,
            mostRecentAddressableMessages: [AddressableMessage],
            nilNonExpiringAddressableMessages: Void,
            isFullDelete: Bool,
        ) {
            self.conversationIdentifier = CodableConversationIdentifier(conversationIdentifier)
            self.mostRecentAddressableMessages = mostRecentAddressableMessages.map { CodableAddressableMessage($0) }
            self.mostRecentNonExpiringAddressableMessages = nil
            self.isFullDelete = isFullDelete
        }
#endif

        init(
            conversationIdentifier: ConversationIdentifier,
            mostRecentAddressableMessages: [AddressableMessage],
            mostRecentNonExpiringAddressableMessages: [AddressableMessage],
            isFullDelete: Bool,
        ) {
            self.conversationIdentifier = CodableConversationIdentifier(conversationIdentifier)
            self.mostRecentAddressableMessages = mostRecentAddressableMessages.map { CodableAddressableMessage($0) }
            self.mostRecentNonExpiringAddressableMessages = mostRecentNonExpiringAddressableMessages.map { CodableAddressableMessage($0) }
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
        let conversationIdentifier: CodableConversationIdentifier

        init(conversationIdentifier: ConversationIdentifier) {
            self.conversationIdentifier = CodableConversationIdentifier(conversationIdentifier)
        }

        fileprivate var asProto: SSKProtoSyncMessageDeleteForMeLocalOnlyConversationDelete {
            let protoBuilder = SSKProtoSyncMessageDeleteForMeLocalOnlyConversationDelete.builder()
            protoBuilder.setConversation(conversationIdentifier.asProto)
            return protoBuilder.buildInfallibly()
        }
    }
}
