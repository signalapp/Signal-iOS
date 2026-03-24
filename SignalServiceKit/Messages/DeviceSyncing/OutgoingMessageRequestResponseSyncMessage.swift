//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSSyncMessageRequestResponseMessage)
public final class OutgoingMessageRequestResponseSyncMessage: OutgoingSyncMessage {

    public enum ResponseType: UInt64 {
        case accept = 0
        case delete = 1
        case block = 2
        case blockAndDelete = 3
        case spam = 4
        case blockAndSpam = 5

        fileprivate var asProtoResponseType: SSKProtoSyncMessageMessageRequestResponseType {
            switch self {
            case .accept: .accept
            case .delete: .delete
            case .block: .block
            case .blockAndDelete: .blockAndDelete
            case .spam: .spam
            case .blockAndSpam: .blockAndSpam
            }
        }
    }

    // v0: The sending thread is also the acted-upon thread.
    // v1: (skipped to avoid ambiguity)
    // v2: The acted-upon thread is stored in groupId/threadAci.
    let version: UInt

    let groupId: Data?
    let threadAci: Aci?
    let responseType: ResponseType

    override public class var supportsSecureCoding: Bool { true }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let groupId {
            coder.encode(groupId, forKey: "groupId")
        }
        coder.encode(NSNumber(value: self.responseType.rawValue), forKey: "responseType")
        if let threadAci {
            coder.encode(threadAci.serviceIdString, forKey: "threadAci")
        }
        coder.encode(NSNumber(value: self.version), forKey: "version")
    }

    public required init?(coder: NSCoder) {
        guard
            let rawResponseType = coder.decodeObject(of: NSNumber.self, forKey: "responseType"),
            let responseType = ResponseType(rawValue: rawResponseType.uint64Value)
        else {
            return nil
        }
        self.responseType = responseType
        self.groupId = coder.decodeObject(of: NSData.self, forKey: "groupId") as Data?
        let threadAciString = coder.decodeObject(of: NSString.self, forKey: "threadAci") as String?
        if let threadAciString {
            guard let threadAci = Aci.parseFrom(aciString: threadAciString) else {
                return nil
            }
            self.threadAci = threadAci
        } else {
            self.threadAci = nil
        }
        self.version = coder.decodeObject(of: NSNumber.self, forKey: "version")?.uintValue ?? 0
        super.init(coder: coder)
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.groupId)
        hasher.combine(self.responseType)
        hasher.combine(self.threadAci)
        hasher.combine(self.version)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.groupId == object.groupId else { return false }
        guard self.responseType == object.responseType else { return false }
        guard self.threadAci == object.threadAci else { return false }
        guard self.version == object.version else { return false }
        return true
    }

    init(
        localThread: TSContactThread,
        messageRequestThread: TSThread,
        responseType: ResponseType,
        tx: DBReadTransaction,
    ) {
        self.version = 2
        switch messageRequestThread {
        case let thread as TSGroupThread:
            self.groupId = thread.groupId
            self.threadAci = nil
        case let thread as TSContactThread:
            self.groupId = nil
            self.threadAci = thread.contactAddress.aci
            owsAssertDebug(self.threadAci != nil, "must have ACI when responding to a message request")
        default:
            self.groupId = nil
            self.threadAci = nil
            owsFailDebug("can't response to thread type")
        }
        self.responseType = responseType
        super.init(localThread: localThread, tx: tx)
    }

    override public func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let messageRequestResponseBuilder = SSKProtoSyncMessageMessageRequestResponse.builder()
        messageRequestResponseBuilder.setType(self.responseType.asProtoResponseType)

        if let groupId {
            messageRequestResponseBuilder.setGroupID(groupId)
        } else if let threadAci {
            messageRequestResponseBuilder.setThreadAciBinary(threadAci.serviceIdBinary)
        } else if self.version < 2 {
            // Fallback behavior. Messages of this version are no longer created.
            // Eventually, all enqueued messages of this type should be resolved
            // (either because they have been sent or because they ran out of retries).
            let thread = self.thread(tx: tx)
            guard let thread else {
                owsFailDebug("Missing thread for message request response")
                return nil
            }

            switch thread {
            case let thread as TSGroupThread:
                messageRequestResponseBuilder.setGroupID(thread.groupModel.groupId)
            case let thread as TSContactThread:
                if let threadAci = thread.contactAddress.serviceId as? Aci {
                    messageRequestResponseBuilder.setThreadAciBinary(threadAci.serviceIdBinary)
                }
            default:
                owsFailDebug("Thread is invalid type for message request response")
                return nil
            }
        }

        let builder = SSKProtoSyncMessage.builder()
        builder.setMessageRequestResponse(messageRequestResponseBuilder.buildInfallibly())
        return builder
    }

    override public var isUrgent: Bool { false }
}
