//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public class NoopCallMessageHandler: CallMessageHandler {
    public init() {}

    public func receivedEnvelope(
        _ envelope: SSKProtoEnvelope,
        callEnvelope: CallEnvelopeType,
        from caller: (aci: Aci, deviceId: UInt32),
        toLocalIdentity localIdentity: OWSIdentity,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        sentAtTimestamp: UInt64,
        serverReceivedTimestamp: UInt64,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        owsFailDebug("")
    }

    public func receivedGroupCallUpdateMessage(
        _ updateMessage: SSKProtoDataMessageGroupCallUpdate,
        forGroupId groupId: GroupIdentifier,
        serverReceivedTimestamp: UInt64
    ) async {
        owsFailDebug("")
    }
}
