//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class MessageProcessor: NSObject {
    private static let maxEnvelopeByteCount = 250 * 1024
    private static let largeEnvelopeWarningByteCount = 25 * 1024
    private static let serialQueue = DispatchQueue(label: "MessageProcessor.processingQueue")

    private struct PendingEnvelope {
        let encryptedEnvelopeData: Data
        let encryptedEnvelope: SSKProtoEnvelope
        let serverDeliveryTimestamp: UInt64
        let completion: (Error?) -> Void
    }

    private static let pendingEnvelopesLock = UnfairLock()
    private static var pendingEnvelopes = [PendingEnvelope]()

    public static func processEncryptedEnvelopes(
        envelopes: [(encryptedEnvelopeData: Data, encryptedEnvelope: SSKProtoEnvelope?, completion: (Error?) -> Void)],
        serverDeliveryTimestamp: UInt64
    ) {
        for envelope in envelopes {
            processEncryptedEnvelopeData(
                envelope.encryptedEnvelopeData,
                encryptedEnvelope: envelope.encryptedEnvelope,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                completion: envelope.completion
            )
        }
    }

    @objc
    public static func processEncryptedEnvelopeData(
        _ encryptedEnvelopeData: Data,
        encryptedEnvelope optionalEncryptedEnvelope: SSKProtoEnvelope? = nil,
        serverDeliveryTimestamp: UInt64,
        completion: @escaping (Error?) -> Void
    ) {
        guard !encryptedEnvelopeData.isEmpty else {
            completion(OWSAssertionError("Empty envelope."))
            return
        }

        // Drop any too-large messages on the floor. Well behaving clients should never send them.
        guard encryptedEnvelopeData.count <= Self.maxEnvelopeByteCount else {
            //        OWSProdError([OWSAnalyticsEvents messageReceiverErrorOversizeMessage]);
            completion(OWSAssertionError("Oversize envelope."))
            return
        }

        // Take note of any messages larger than we expect, but still process them.
        // This likely indicates a misbehaving sending client.
        if encryptedEnvelopeData.count > Self.largeEnvelopeWarningByteCount {
            //        OWSProdError([OWSAnalyticsEvents messageReceiverErrorLargeMessage]);
            owsFailDebug("Unexpectedly large envelope.")
        }

        let encryptedEnvelope: SSKProtoEnvelope
        if let optionalEncryptedEnvelope = optionalEncryptedEnvelope {
            encryptedEnvelope = optionalEncryptedEnvelope
        } else {
            do {
                encryptedEnvelope = try SSKProtoEnvelope(serializedData: encryptedEnvelopeData)
            } catch {
                owsFailDebug("Failed to parse encrypted envelope \(error)")
                completion(error)
                return
            }
        }

        pendingEnvelopesLock.withLock {
            pendingEnvelopes.append(PendingEnvelope(
                encryptedEnvelopeData: encryptedEnvelopeData,
                encryptedEnvelope: encryptedEnvelope,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                completion: completion
            ))
        }

        serialQueue.async { self.parseEnvelopes() }
    }

    public static func parseEnvelopes() {
        assertOnQueue(serialQueue)

        let batchSize = 5
        let batchEnvelopes = pendingEnvelopesLock.withLock {
            pendingEnvelopes.prefix(batchSize)
        }

        guard !batchEnvelopes.isEmpty else { return }

        SDSDatabaseStorage.shared.write { transaction in
            for pendingEnvelope in batchEnvelopes {
                self.parseEnvelope(pendingEnvelope, transaction: transaction)
            }

            // Remove the processed envelopes from the pending list.
            pendingEnvelopesLock.withLock {
                guard pendingEnvelopes.count > batchEnvelopes.count else {
                    pendingEnvelopes = []
                    return
                }
                pendingEnvelopes = Array(pendingEnvelopes.suffix(from: batchEnvelopes.count))
            }
        }
    }

    private static func parseEnvelope(_ pendingEnvelope: PendingEnvelope, transaction: SDSAnyWriteTransaction) {
        assertOnQueue(serialQueue)

        let result = SSKEnvironment.shared.messageDecrypter.decryptEnvelope(
            pendingEnvelope.encryptedEnvelope,
            envelopeData: pendingEnvelope.encryptedEnvelopeData,
            transaction: transaction
        )

        switch result {
        case .success(let result):
            let envelope: SSKProtoEnvelope
            do {
                // NOTE: We use envelopeData from the decrypt result, not the pending envelope,
                // since the envelope may be altered by the decryption process in the UD case.
                envelope = try SSKProtoEnvelope(serializedData: result.envelopeData)
            } catch {
                owsFailDebug("Failed to parse decrypted envelope \(error)")
                transaction.addAsyncCompletionOffMain { pendingEnvelope.completion(error) }
                return
            }

            if let groupContextV2 = GroupsV2MessageProcessor.groupContextV2(
                forEnvelope: envelope,
                plaintextData: result.plaintextData
            ), !GroupsV2MessageProcessor.canContextBeProcessedImmediately(
                groupContext: groupContextV2,
                transaction: transaction
            ) {
                // If we can't process the message immediately, we enqueue it for
                // for processing in the same transaction within which it was decrypted
                // to prevent data loss.
                SSKEnvironment.shared.groupsV2MessageProcessor.enqueue(
                    envelopeData: result.envelopeData,
                    plaintextData: result.plaintextData,
                    envelope: envelope,
                    wasReceivedByUD: wasReceivedByUD(envelope: pendingEnvelope.encryptedEnvelope),
                    serverDeliveryTimestamp: pendingEnvelope.serverDeliveryTimestamp,
                    transaction: transaction
                )
            } else {
                // Envelopes can be processed immediately if they're:
                // 1. Not a GV2 message.
                // 2. A GV2 message that doesn't require updating the group.
                //
                // The advantage to processing the message immediately is that
                // we can full process the message in the same transaction that
                // we used to decrypt it. This results in a significant perf
                // benefit verse queueing the message and waiting for that queue
                // to open new transactions and process messages. The downside is
                // that if we *fail* to process this message (e.g. the app crashed
                // or was killed), we'll have to re-decrypt again before we process.
                // This is safe, since the decrypt operation would also be rolled
                // back (since the transaction didn't finalize) and should be rare.
                SSKEnvironment.shared.messageManager.processEnvelope(
                    envelope,
                    plaintextData: result.plaintextData,
                    wasReceivedByUD: wasReceivedByUD(envelope: pendingEnvelope.encryptedEnvelope),
                    serverDeliveryTimestamp: pendingEnvelope.serverDeliveryTimestamp,
                    transaction: transaction
                )
            }

            transaction.addAsyncCompletionOffMain { pendingEnvelope.completion(nil) }
        case .failure(let error):
            transaction.addAsyncCompletionOffMain {
                pendingEnvelope.completion(error)
            }
        }
    }

    private static func wasReceivedByUD(envelope: SSKProtoEnvelope) -> Bool {
        let hasSenderSource: Bool
        if envelope.hasValidSource {
            hasSenderSource = true
        } else {
            hasSenderSource = false
        }
        return envelope.type == .unidentifiedSender && !hasSenderSource
    }
}
