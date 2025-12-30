//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

public class CallLinkProfileKeySharingManager {
    private var consideredAcis = Set<Aci>()

    private let db: any DB
    private let accountManager: TSAccountManager

    init(db: any DB, accountManager: TSAccountManager) {
        self.db = db
        self.accountManager = accountManager
    }

    @MainActor
    func sendProfileKeyToCallMembers(
        acis: [Aci],
        blockingManager: BlockingManager,
    ) {
        var unconsideredAcis = [Aci]()

        for aci in acis {
            if !consideredAcis.contains(aci) {
                unconsideredAcis.append(aci)
            }
        }

        let eligibleAcisNotSentProfileKeyYet = unconsideredAcis.filter { aci in
            return db.read { tx in
                let isLocal = accountManager.localIdentifiers(tx: tx)?.aci == aci

                let address = SignalServiceAddress(aci)
                let isBlocked = blockingManager.isAddressBlocked(
                    address,
                    transaction: tx,
                )

                let isEligible = !isLocal && !isBlocked

                if !isEligible {
                    consideredAcis.insert(aci)
                }

                return isEligible
            }
        }

        if eligibleAcisNotSentProfileKeyYet.isEmpty { return }

        self.consideredAcis.formUnion(eligibleAcisNotSentProfileKeyYet)
        db.asyncWrite { tx in
            let profileManager = SSKEnvironment.shared.profileManagerRef
            let profileKey = profileManager.localProfileKey(tx: tx)!
            for aci in eligibleAcisNotSentProfileKeyYet {
                self.sendProfileKey(profileKey, toAci: aci, tx: tx)
            }
        }
    }

    private func sendProfileKey(_ profileKey: ProfileKey, toAci aci: Aci, tx: DBWriteTransaction) {
        let thread = TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(aci), transaction: tx)
        let profileKeyMessage = OWSProfileKeyMessage(
            thread: thread,
            profileKey: profileKey.serialize(),
            transaction: tx,
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: profileKeyMessage,
        )
        let sendPromise = SSKEnvironment.shared.messageSenderJobQueueRef.add(
            .promise,
            message: preparedMessage,
            transaction: tx,
        )
        Task { @MainActor in
            do {
                try await sendPromise.awaitable()
            } catch is SpamChallengeRequiredError {
                Logger.warn("Marking \(aci) as eligible for another attempt because of a captcha.")
                self.consideredAcis.remove(aci)
            }
        }
    }
}

extension CallLinkProfileKeySharingManager: GroupCallObserver {
    func groupCallPeekChanged(_ call: GroupCall) {
        sendProfileKeyToParticipants(ofCall: call)
    }

    @MainActor
    func sendProfileKeyToParticipants(ofCall call: GroupCall) {
        switch call.concreteType {
        case .groupThread:
            return
        case .callLink(let callLinkCall):
            if
                callLinkCall.localUserHasConsentedToJoin(),
                let acis = callLinkCall.ringRtcCall.peekInfo?.joinedMembers.map({ Aci(fromUUID: $0) })
            {
                sendProfileKeyToCallMembers(
                    acis: acis,
                    blockingManager: SSKEnvironment.shared.blockingManagerRef,
                )
            }
        }
    }
}

private extension CallLinkCall {
    func localUserHasConsentedToJoin() -> Bool {
        switch self.joinState {
        case .notJoined:
            return false
        case .joining, .pending, .joined:
            return true
        }
    }
}
