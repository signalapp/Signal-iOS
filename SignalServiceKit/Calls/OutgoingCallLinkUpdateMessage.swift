//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalRingRTC

@objc(OutgoingCallLinkUpdateMessage)
public class OutgoingCallLinkUpdateMessage: OWSOutgoingSyncMessage {
    public required init?(coder: NSCoder) {
        self.adminPasskey = coder.decodeObject(of: NSData.self, forKey: "adminPasskey") as Data?
        self.rootKey = coder.decodeObject(of: NSData.self, forKey: "rootKey") as Data?
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let adminPasskey {
            coder.encode(adminPasskey, forKey: "adminPasskey")
        }
        if let rootKey {
            coder.encode(rootKey, forKey: "rootKey")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(adminPasskey)
        hasher.combine(rootKey)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.adminPasskey == object.adminPasskey else { return false }
        guard self.rootKey == object.rootKey else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.adminPasskey = self.adminPasskey
        result.rootKey = self.rootKey
        return result
    }

    private var rootKey: Data!
    private var adminPasskey: Data?

    public init(
        localThread: TSContactThread,
        rootKey: CallLinkRootKey,
        adminPasskey: Data?,
        tx: DBReadTransaction,
    ) {
        self.rootKey = rootKey.bytes
        self.adminPasskey = adminPasskey
        super.init(localThread: localThread, transaction: tx)
    }

    override public var isUrgent: Bool { false }

    override public func syncMessageBuilder(transaction: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let callLinkUpdateBuilder = SSKProtoSyncMessageCallLinkUpdate.builder()
        callLinkUpdateBuilder.setType(.update)
        callLinkUpdateBuilder.setRootKey(self.rootKey)
        if let adminPasskey = self.adminPasskey {
            callLinkUpdateBuilder.setAdminPasskey(adminPasskey)
        }

        let builder = SSKProtoSyncMessage.builder()
        builder.setCallLinkUpdate(callLinkUpdateBuilder.buildInfallibly())
        return builder
    }
}
