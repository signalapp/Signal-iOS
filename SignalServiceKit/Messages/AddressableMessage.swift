//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Represents a message that can be "addressed" stably across clients.
struct AddressableMessage {
    enum Author {
        case aci(Aci)
        case e164(E164)
    }

    let author: Author
    let sentTimestamp: UInt64

    init(author: Author, sentTimestamp: UInt64) {
        self.author = author
        self.sentTimestamp = sentTimestamp
    }

    init?(message: TSMessage, localIdentifiers: LocalIdentifiers) {
        if let incomingMessage = message as? TSIncomingMessage {
            self.init(incomingMessage: incomingMessage)
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            self.init(outgoingMessage: outgoingMessage, localIdentifiers: localIdentifiers)
        } else {
            return nil
        }
    }

    init?(incomingMessage: TSIncomingMessage) {
        if let authorAci = incomingMessage.authorAddress.aci {
            author = .aci(authorAci)
        } else if let authorE164 = incomingMessage.authorAddress.e164 {
            author = .e164(authorE164)
        } else {
            return nil
        }

        sentTimestamp = incomingMessage.timestamp
    }

    init(outgoingMessage: TSOutgoingMessage, localIdentifiers: LocalIdentifiers) {
        author = .aci(localIdentifiers.aci)
        sentTimestamp = outgoingMessage.timestamp
    }

    init?(proto: SSKProtoAddressableMessage) {
        guard proto.hasSentTimestamp, SDS.fitsInInt64(proto.sentTimestamp) else {
            return nil
        }

        if
            let authorAci = ServiceId.parseFrom(
                serviceIdBinary: proto.authorServiceIDBinary,
                serviceIdString: proto.authorServiceID,
            ) as? Aci
        {
            author = .aci(authorAci)
        } else if let authorE164 = E164(proto.authorE164) {
            author = .e164(authorE164)
        } else {
            return nil
        }

        sentTimestamp = proto.sentTimestamp
    }

    var asProto: SSKProtoAddressableMessage {
        let protoBuilder = SSKProtoAddressableMessage.builder()
        protoBuilder.setSentTimestamp(sentTimestamp)
        switch author {
        case .aci(let aci):
            if BuildFlags.serviceIdBinaryOneOf {
                protoBuilder.setAuthorServiceIDBinary(aci.serviceIdBinary)
            } else {
                protoBuilder.setAuthorServiceID(aci.serviceIdString)
            }
        case .e164(let e164): protoBuilder.setAuthorE164(e164.stringValue)
        }
        return protoBuilder.buildInfallibly()
    }
}

// MARK: -

enum ConversationIdentifier {
    case serviceId(ServiceId)
    case e164(E164)
    case groupIdentifier(GroupIdentifier)

    init?(proto: SSKProtoConversationIdentifier) {
        if
            let serviceId = ServiceId.parseFrom(
                serviceIdBinary: proto.threadServiceIDBinary,
                serviceIdString: proto.threadServiceID,
            )
        {
            self = .serviceId(serviceId)
        } else if let e164 = E164(proto.threadE164) {
            self = .e164(e164)
        } else if
            let groupIdData = proto.threadGroupID,
            let groupIdentifier = try? GroupIdentifier(contents: groupIdData)
        {
            self = .groupIdentifier(groupIdentifier)
        } else {
            return nil
        }
    }

    var asProto: SSKProtoConversationIdentifier {
        let protoBuilder = SSKProtoConversationIdentifier.builder()
        switch self {
        case .serviceId(let serviceId):
            if BuildFlags.serviceIdBinaryOneOf {
                protoBuilder.setThreadServiceIDBinary(serviceId.serviceIdBinary)
            } else {
                protoBuilder.setThreadServiceID(serviceId.serviceIdString)
            }
        case .e164(let e164): protoBuilder.setThreadE164(e164.stringValue)
        case .groupIdentifier(let groupIdentifier): protoBuilder.setThreadGroupID(groupIdentifier.serialize())
        }
        return protoBuilder.buildInfallibly()
    }
}
