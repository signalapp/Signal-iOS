//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient
import SignalRingRTC

public class CallOfferHandlerImpl {
    private let identityManager: any OWSIdentityManager
    private let notificationPresenter: NotificationPresenter
    private let profileManager: any ProfileManager
    private let tsAccountManager: any TSAccountManager

    public init(
        identityManager: any OWSIdentityManager,
        notificationPresenter: NotificationPresenter,
        profileManager: any ProfileManager,
        tsAccountManager: any TSAccountManager
    ) {
        self.identityManager = identityManager
        self.notificationPresenter = notificationPresenter
        self.profileManager = profileManager
        self.tsAccountManager = tsAccountManager
    }

    public struct PartialResult {
        public let identityKeys: CallIdentityKeys
        public let offerMediaType: TSRecentCallOfferType
        public let thread: TSContactThread
    }

    public func insertMissedCallInteraction(
        for callId: UInt64,
        in thread: TSContactThread,
        outcome: RPRecentCallType,
        callType: TSRecentCallOfferType,
        sentAtTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        let callEventInserter = CallEventInserter(
            thread: thread,
            callId: callId,
            offerMediaType: callType,
            sentAtTimestamp: sentAtTimestamp
        )
        callEventInserter.createOrUpdate(callType: outcome, tx: tx)
    }

    public func startHandlingOffer(
        caller: Aci,
        sourceDevice: UInt32,
        localIdentity: OWSIdentity,
        callId: UInt64,
        callType: SSKProtoCallMessageOfferType,
        sentAtTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) -> PartialResult? {
        let thread = TSContactThread.getOrCreateThread(
            withContactAddress: SignalServiceAddress(caller),
            transaction: tx
        )

        let offerMediaType: TSRecentCallOfferType
        switch callType {
        case .offerAudioCall:
            offerMediaType = .audio
        case .offerVideoCall:
            offerMediaType = .video
        }

        func insertMissedCallInteraction(outcome: RPRecentCallType, tx: SDSAnyWriteTransaction) {
            return self.insertMissedCallInteraction(
                for: callId,
                in: thread,
                outcome: outcome,
                callType: offerMediaType,
                sentAtTimestamp: sentAtTimestamp,
                tx: tx
            )
        }

        guard tsAccountManager.registrationState(tx: tx.asV2Read).isRegistered else {
            Logger.warn("user is not registered, skipping call.")
            insertMissedCallInteraction(outcome: .incomingMissed, tx: tx)
            return nil
        }

        let untrustedIdentity = identityManager.untrustedIdentityForSending(
            to: SignalServiceAddress(caller),
            untrustedThreshold: nil,
            tx: tx.asV2Read
        )
        if let untrustedIdentity {
            Logger.warn("missed a call due to untrusted identity")

            let notificationInfo = CallNotificationInfo(
                groupingId: UUID(),
                thread: thread,
                caller: caller
            )

            switch untrustedIdentity.verificationState {
            case .verified, .defaultAcknowledged:
                owsFailDebug("shouldn't have missed a call due to untrusted identity if the identity is verified")
                let sentAtTimestamp = Date(millisecondsSince1970: sentAtTimestamp)
                self.notificationPresenter.notifyUserOfMissedCall(
                    notificationInfo: notificationInfo,
                    offerMediaType: offerMediaType,
                    sentAt: sentAtTimestamp,
                    tx: tx
                )
            case .default:
                self.notificationPresenter.notifyUserOfMissedCallBecauseOfNewIdentity(
                    notificationInfo: notificationInfo,
                    tx: tx
                )
            case .noLongerVerified:
                self.notificationPresenter.notifyUserOfMissedCallBecauseOfNoLongerVerifiedIdentity(
                    notificationInfo: notificationInfo,
                    tx: tx
                )
            }

            insertMissedCallInteraction(outcome: .incomingMissedBecauseOfChangedIdentity, tx: tx)
            return nil
        }

        guard let identityKeys = identityManager.getCallIdentityKeys(remoteAci: caller, tx: tx) else {
            Logger.warn("missing identity keys, skipping call.")
            insertMissedCallInteraction(outcome: .incomingMissed, tx: tx)
            return nil
        }

        guard allowsInboundCalls(from: caller, tx: tx) else {
            Logger.info("Ignoring call offer from \(caller) due to insufficient permissions.")

            // Send the need permission message to the caller, so they know why we rejected their call.
            switch localIdentity {
            case .aci:
                _ = CallHangupSender.sendHangup(
                    thread: thread,
                    callId: callId,
                    hangupType: .hangupNeedPermission,
                    localDeviceId: tsAccountManager.storedDeviceId(tx: tx.asV2Read),
                    remoteDeviceId: sourceDevice,
                    tx: tx
                )
            case .pni:
                // Don't respond if they sent the offer to our PNI.
                break
            }

            // Store the call as a missed call for the local user. They will see it in the conversation
            // along with the message request dialog. When they accept the dialog, they can call back
            // or the caller can try again.
            insertMissedCallInteraction(outcome: .incomingMissed, tx: tx)
            return nil
        }

        return PartialResult(
            identityKeys: identityKeys,
            offerMediaType: offerMediaType,
            thread: thread
        )
    }

    private func allowsInboundCalls(from caller: Aci, tx: SDSAnyReadTransaction) -> Bool {
        // If the thread is in our whitelist, then we've either trusted it manually
        // or it's a chat with someone in our system contacts.
        return profileManager.isUser(inProfileWhitelist: SignalServiceAddress(caller), transaction: tx)
    }
}

public struct CallIdentityKeys {
    public let localIdentityKey: IdentityKey
    public let contactIdentityKey: IdentityKey
}

extension OWSIdentityManager {
    public func getCallIdentityKeys(
        remoteAci: Aci,
        tx: SDSAnyReadTransaction
    ) -> CallIdentityKeys? {
        guard let localIdentityKey = identityKeyPair(for: .aci, tx: tx.asV2Read)?.keyPair.identityKey else {
            owsFailDebug("missing localIdentityKey")
            return nil
        }
        guard let contactIdentityKey = try? identityKey(for: remoteAci, tx: tx.asV2Read) else {
            owsFailDebug("missing contactIdentityKey")
            return nil
        }
        return CallIdentityKeys(localIdentityKey: localIdentityKey, contactIdentityKey: contactIdentityKey)
    }
}

public enum CallHangupSender {
    public static func sendHangup(
        thread: TSContactThread,
        callId: UInt64,
        hangupType: SSKProtoCallMessageHangupType,
        localDeviceId: UInt32,
        remoteDeviceId: UInt32?,
        tx: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        let hangupBuilder = SSKProtoCallMessageHangup.builder(id: callId)

        hangupBuilder.setType(hangupType)

        if hangupType != .hangupNormal {
            // deviceId is optional and only used when indicated by a hangup due to
            // a call being accepted elsewhere.
            hangupBuilder.setDeviceID(localDeviceId)
        }

        let hangupMessage: SSKProtoCallMessageHangup
        do {
            hangupMessage = try hangupBuilder.build()
        } catch {
            owsFailDebug("Couldn't build hangup message.")
            return Promise(error: error)
        }

        let callMessage = OWSOutgoingCallMessage(
            thread: thread,
            hangupMessage: hangupMessage,
            destinationDeviceId: remoteDeviceId.map(NSNumber.init(value:)),
            transaction: tx
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: callMessage
        )
        return ThreadUtil.enqueueMessagePromise(
            message: preparedMessage,
            limitToCurrentProcessLifetime: true,
            isHighPriority: true,
            transaction: tx
        )
    }
}
