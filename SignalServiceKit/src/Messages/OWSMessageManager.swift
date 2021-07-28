//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient

@objc
public enum SealedSenderContentHint: Int {
    case `default` = 0
    case resendable
    case implicit

    init(_ signalClientHint: UnidentifiedSenderMessageContent.ContentHint) {
        switch signalClientHint {
        case .default: self = .default
        case .resendable: self = .resendable
        case .implicit: self = .implicit
        default:
            owsFailDebug("Unspecified case \(signalClientHint)")
            self = .default
        }
    }

    public var signalClientHint: UnidentifiedSenderMessageContent.ContentHint {
        switch self {
        case .default: return .default
        case .resendable: return .resendable
        case .implicit: return .implicit
        }
    }
}

extension OWSMessageManager {

    @objc
    func handleIncomingEnvelope(
        _ envelope: SSKProtoEnvelope,
        withSenderKeyDistributionMessage skdmData: Data,
        transaction writeTx: SDSAnyWriteTransaction) {

        guard let sourceAddress = envelope.sourceAddress, sourceAddress.isValid else {
            return owsFailDebug("Invalid source address")
        }

        do {
            let skdm = try SenderKeyDistributionMessage(bytes: skdmData.map { $0 })
            let sourceDeviceId = envelope.sourceDevice
            let protocolAddress = try ProtocolAddress(from: sourceAddress, deviceId: sourceDeviceId)
            try processSenderKeyDistributionMessage(skdm, from: protocolAddress, store: senderKeyStore, context: writeTx)
        } catch {
            owsFailDebug("Failed to process incoming sender key \(error)")
        }
    }

    @objc
    func handleIncomingEnvelope(
        _ envelope: SSKProtoEnvelope,
        withDecryptionErrorMessage bytes: Data,
        transaction writeTx: SDSAnyWriteTransaction
    ) {
        guard let sourceAddress = envelope.sourceAddress, sourceAddress.isValid else {
            return owsFailDebug("Invalid source address")
        }
        let sourceDeviceId = envelope.sourceDevice

        do {
            let errorMessage = try DecryptionErrorMessage(bytes: bytes)
            guard errorMessage.deviceId == tsAccountManager.storedDeviceId() else {
                Logger.info("Received a DecryptionError message targeting a linked device. Ignoring.")
                return
            }
            let protocolAddress = try ProtocolAddress(from: sourceAddress, deviceId: sourceDeviceId)

            // If a ratchet key is included, this was a 1:1 session message
            // Archive the session if the current key matches.
            let didPerformSessionReset: Bool
            if let ratchetKey = errorMessage.ratchetKey {
                let sessionRecord = try sessionStore.loadSession(for: protocolAddress, context: writeTx)
                if try sessionRecord?.currentRatchetKeyMatches(ratchetKey) == true {
                    Logger.info("Decryption error included ratchet key. Archiving...")
                    sessionStore.archiveSession(for: sourceAddress,
                                                deviceId: Int32(sourceDeviceId),
                                                transaction: writeTx)
                    didPerformSessionReset = true
                } else {
                    Logger.info("Ratchet key mismatch. Leaving session as-is.")
                    didPerformSessionReset = false
                }
            } else {
                didPerformSessionReset = false
            }

            Logger.warn("Performing message resend of timestamp \(errorMessage.timestamp)")
            let resendResponse = OWSOutgoingResendResponse(
                address: sourceAddress,
                deviceId: Int64(sourceDeviceId),
                failedTimestamp: Int64(errorMessage.timestamp),
                didResetSession: didPerformSessionReset,
                transaction: writeTx
            )

            if let resendResponse = resendResponse {
                messageSenderJobQueue.add(message: resendResponse.asPreparer, transaction: writeTx)
            }

        } catch {
            owsFailDebug("Failed to process decryption error message \(error)")
        }
    }
}
