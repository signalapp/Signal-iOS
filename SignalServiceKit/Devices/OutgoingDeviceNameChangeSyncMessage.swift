//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Informs other platforms that a linked device's name has changed, and they
/// should refresh their list of linked devices.
@objc(OutgoingDeviceNameChangeSyncMessage)
public class OutgoingDeviceNameChangeSyncMessage: OWSOutgoingSyncMessage {

    /// Exposed and nullable for compatibility with Mantle.
    @objc(deviceId)
    private(set) var deviceId: NSNumber!

    init(
        deviceId: UInt32,
        thread: TSThread,
        tx: SDSAnyReadTransaction
    ) {
        self.deviceId = NSNumber(value: deviceId)
        super.init(thread: thread, transaction: tx)
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required public init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    override public var isUrgent: Bool { false }

    override public func syncMessageBuilder(transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let deviceNameChangeBuilder = SSKProtoSyncMessageDeviceNameChange.builder()
        deviceNameChangeBuilder.setDeviceID(deviceId.uint32Value)

        let builder = SSKProtoSyncMessage.builder()
        builder.setDeviceNameChange(deviceNameChangeBuilder.buildInfallibly())
        return builder
    }
}
