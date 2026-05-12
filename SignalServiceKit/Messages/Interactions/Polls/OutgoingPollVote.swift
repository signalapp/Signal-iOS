//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class OutgoingPollVoteMessage: TransientOutgoingMessage {
    override public class var supportsSecureCoding: Bool { true }

    public required init?(coder: NSCoder) {
        guard
            let targetPollAuthorAciBinary = coder.decodeObject(of: NSData.self, forKey: "targetPollAuthorAciBinary") as Data?,
            let targetPollAuthorAci = try? Aci.parseFrom(serviceIdBinary: targetPollAuthorAciBinary)
        else {
            return nil
        }
        self.targetPollAuthorAci = targetPollAuthorAci
        guard let targetPollTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "targetPollTimestamp") else {
            return nil
        }
        self.targetPollTimestamp = targetPollTimestamp.uint64Value
        guard let voteCount = coder.decodeObject(of: NSNumber.self, forKey: "voteCount") else {
            return nil
        }
        self.voteCount = voteCount.int32Value
        guard let voteOptionIndexes = coder.decodeArrayOfObjects(ofClass: NSNumber.self, forKey: "voteOptionIndexes") else {
            return nil
        }
        self.voteOptionIndexes = voteOptionIndexes.map(\.uint32Value)
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(self.targetPollAuthorAci.serviceIdBinary, forKey: "targetPollAuthorAciBinary")
        coder.encode(NSNumber(value: self.targetPollTimestamp), forKey: "targetPollTimestamp")
        coder.encode(NSNumber(value: self.voteCount), forKey: "voteCount")
        coder.encode(self.voteOptionIndexes, forKey: "voteOptionIndexes")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(targetPollAuthorAci)
        hasher.combine(targetPollTimestamp)
        hasher.combine(voteCount)
        hasher.combine(voteOptionIndexes)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.targetPollAuthorAci == object.targetPollAuthorAci else { return false }
        guard self.targetPollTimestamp == object.targetPollTimestamp else { return false }
        guard self.voteCount == object.voteCount else { return false }
        guard self.voteOptionIndexes == object.voteOptionIndexes else { return false }
        return true
    }

    let targetPollTimestamp: UInt64
    let targetPollAuthorAci: Aci
    let voteOptionIndexes: [UInt32]
    let voteCount: Int32

    public init(
        thread: TSThread,
        targetPollTimestamp: UInt64,
        targetPollAuthorAci: Aci,
        voteOptionIndexes: [UInt32],
        voteCount: Int32,
        tx: DBReadTransaction,
    ) {
        self.targetPollTimestamp = targetPollTimestamp
        self.targetPollAuthorAci = targetPollAuthorAci
        self.voteOptionIndexes = voteOptionIndexes
        self.voteCount = voteCount

        super.init(
            outgoingMessageWith: .withDefaultValues(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override var contentHint: SealedSenderContentHint { .implicit }

    override public func dataMessageBuilder(
        with thread: TSThread,
        transaction: DBReadTransaction,
    ) -> SSKProtoDataMessageBuilder? {
        guard
            let dataMessageBuilder = super.dataMessageBuilder(
                with: thread,
                transaction: transaction,
            )
        else {
            return nil
        }

        let pollVoteBuilder = SSKProtoDataMessagePollVote.builder()

        pollVoteBuilder.setTargetSentTimestamp(targetPollTimestamp)

        pollVoteBuilder.setTargetAuthorAciBinary(targetPollAuthorAci.serviceIdBinary)

        pollVoteBuilder.setOptionIndexes(voteOptionIndexes)

        pollVoteBuilder.setVoteCount(UInt32(clamping: voteCount))

        dataMessageBuilder.setPollVote(
            pollVoteBuilder.buildInfallibly(),
        )

        return dataMessageBuilder
    }

    override public func updateWithSendSuccess(tx: DBWriteTransaction) {
        do {
            try DependenciesBridge.shared.pollMessageManager.processPollVoteMessageDidSend(
                targetPollTimestamp: targetPollTimestamp,
                targetPollAuthorAci: targetPollAuthorAci,
                optionIndexes: voteOptionIndexes,
                voteCount: voteCount,
                threadUniqueId: threadUniqueId,
                tx: tx,
            )
        } catch {
            Logger.error("Failed to update vote message as sent: \(error)")
        }
    }

    override public func updateWithAllSendingRecipientsMarkedAsFailed(
        error: (any Error)? = nil,
        transaction tx: DBWriteTransaction,
    ) {
        super.updateWithAllSendingRecipientsMarkedAsFailed(error: error, transaction: tx)

        revertLocalStateIfFailedForEveryone(tx: tx)
    }

    private func revertLocalStateIfFailedForEveryone(tx: DBWriteTransaction) {
        // Do nothing if we successfully delivered to anyone. Only cleanup
        // local state if we fail to deliver to anyone.
        guard sentRecipientAddresses().isEmpty else {
            Logger.warn("Failed to send poll vote to some recipients")
            return
        }

        guard
            let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci,
            let localRecipientId = DependenciesBridge.shared.recipientDatabaseTable.fetchRecipient(
                serviceId: localAci,
                transaction: tx,
            )?.id
        else {
            owsFailDebug("Missing local aci or recipient")
            return
        }

        Logger.error("Failed to send vote to all recipients.")

        do {
            guard
                let targetMessage = try DependenciesBridge.shared.interactionStore.fetchMessage(
                    timestamp: targetPollTimestamp,
                    incomingMessageAuthor: targetPollAuthorAci == localAci ? nil : targetPollAuthorAci,
                    threadUniqueId: threadUniqueId,
                    transaction: tx,
                ),
                let interactionId = targetMessage.grdbId?.int64Value
            else {
                Logger.error("Can't find target poll")
                return
            }

            try PollStore().revertVoteCount(
                voteCount: voteCount,
                interactionId: interactionId,
                voteAuthorId: localRecipientId,
                transaction: tx,
            )

            SSKEnvironment.shared.databaseStorageRef.touch(interaction: targetMessage, shouldReindex: false, tx: tx)
        } catch {
            Logger.error("Failed to revert vote count: \(error)")
        }
    }
}
