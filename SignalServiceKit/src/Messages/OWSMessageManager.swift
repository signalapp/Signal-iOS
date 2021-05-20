//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalClient

extension OWSMessageManager {

    @objc
    func handleIncomingEnvelope(
        _ envelope: SSKProtoEnvelope,
        withSenderKeyDistributionMessage skdmData: Data,
        transaction writeTx: SDSAnyWriteTransaction) {

        guard envelope.sourceAddress?.isValid == true else {
            return owsFailDebug("Invalid source address")
        }

        do {
            let skdm = try SenderKeyDistributionMessage(bytes: skdmData.map { $0 })
            guard let sourceAddress = envelope.sourceUuid else {
                throw OWSAssertionError("SenderKeyDistributionMessages must be sent from senders with UUID")
            }
            let sourceDeviceId = envelope.sourceDevice
            let protocolAddress = try ProtocolAddress(name: sourceAddress, deviceId: sourceDeviceId)
            try processSenderKeyDistributionMessage(skdm, from: protocolAddress, store: senderKeyStore, context: writeTx)
        } catch {
            owsFailDebug("Failed to process incoming sender key \(error)")
        }
    }
}
