//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Informs other platforms that a linked device's name has changed, and they
/// should refresh their list of linked devices.
@objc(OutgoingDeviceNameChangeSyncMessage)
public class OutgoingDeviceNameChangeSyncMessage: OWSOutgoingSyncMessage {
    public required init?(coder: NSCoder) {
        self.deviceId = coder.decodeObject(of: NSNumber.self, forKey: "deviceId")
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let deviceId {
            coder.encode(deviceId, forKey: "deviceId")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(deviceId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.deviceId == object.deviceId else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.deviceId = self.deviceId
        return result
    }

    private(set) var deviceId: NSNumber!

    init(
        deviceId: UInt32,
        localThread: TSContactThread,
        tx: DBReadTransaction,
    ) {
        self.deviceId = NSNumber(value: deviceId)
        super.init(localThread: localThread, transaction: tx)
    }

    override public var isUrgent: Bool { false }

    override public func syncMessageBuilder(transaction: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let deviceNameChangeBuilder = SSKProtoSyncMessageDeviceNameChange.builder()
        deviceNameChangeBuilder.setDeviceID(deviceId.uint32Value)

        let builder = SSKProtoSyncMessage.builder()
        builder.setDeviceNameChange(deviceNameChangeBuilder.buildInfallibly())
        return builder
    }
}
