//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public extension InteractionStore {
    /// Fetch the interaction, of the specified type, associated with the given
    /// call record.
    func fetchAssociatedInteraction<InteractionType>(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) -> InteractionType? {
        guard
            let interaction = fetchInteraction(
                rowId: callRecord.interactionRowId, tx: tx
            ) as? InteractionType
        else {
            CallRecordLogger.shared.error(
                "Missing associated interaction for call record. This should be impossible per the DB schema!"
            )
            return nil
        }

        return interaction
    }

    // MARK: - Individual call interactions

    /// Update the `callType` of an individual-call interaction.
    func updateIndividualCallInteractionType(
        individualCallInteraction: TSCall,
        newCallInteractionType: RPRecentCallType,
        tx: DBWriteTransaction
    ) {
        updateInteraction(individualCallInteraction, tx: tx) { individualCallInteraction in
            individualCallInteraction.callType = newCallInteractionType
        }
    }

    // MARK: - Group call interactions

    /// Inserts a group call interaction without any group call membership info.
    /// - Returns
    /// The inserted interaction and its SQLite row ID.
    func insertGroupCallInteraction(
        joinedMemberAcis: [Aci] = [],
        creatorAci: Aci? = nil,
        groupThread: TSGroupThread,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    ) -> (OWSGroupCallMessage, Int64) {
        let groupCallInteraction = OWSGroupCallMessage(
            joinedMemberAcis: joinedMemberAcis.map { AciObjC($0) },
            creatorAci: creatorAci.map { AciObjC($0) },
            thread: groupThread,
            sentAtTimestamp: callEventTimestamp
        )
        insertInteraction(groupCallInteraction, tx: tx)

        guard let interactionRowId = groupCallInteraction.sqliteRowId else {
            owsFail("Missing SQLite row ID for just-inserted interaction!")
        }

        return (groupCallInteraction, interactionRowId)
    }

    /// Update the joined members and creator of a group call on the associated
    /// group-call interaction.
    ///
    /// - Parameter notificationScheduler
    /// A scheduler on which to post a ``GroupCallInteractionUpdatedNotification``
    /// about the update.
    func updateGroupCallInteractionAcis(
        groupCallInteraction: OWSGroupCallMessage,
        joinedMemberAcis: [Aci],
        creatorAci: Aci,
        callId: UInt64,
        groupThreadRowId: Int64,
        notificationScheduler: Scheduler,
        tx: DBWriteTransaction
    ) {
        updateInteraction(groupCallInteraction, tx: tx) { groupCallInteraction in
            groupCallInteraction.hasEnded = joinedMemberAcis.isEmpty
            groupCallInteraction.creatorUuid = creatorAci.serviceIdUppercaseString
            groupCallInteraction.joinedMemberUuids = joinedMemberAcis.map { $0.serviceIdUppercaseString }
        }

        tx.addAsyncCompletion(on: notificationScheduler) {
            NotificationCenter.default.post(GroupCallInteractionUpdatedNotification(
                callId: callId,
                groupThreadRowId: groupThreadRowId
            ).asNotification)
        }
    }
}

// MARK: - Group call interaction updated notification

public struct GroupCallInteractionUpdatedNotification {
    private enum UserInfoKeys {
        static let callId: String = "callId"
        static let groupThreadRowId: String = "groupThreadRowId"
    }

    public static let name: NSNotification.Name = .init("GroupCallInteractionUpdatedNotification")

    public let callId: UInt64
    public let groupThreadRowId: Int64

    init(
        callId: UInt64,
        groupThreadRowId: Int64
    ) {
        self.callId = callId
        self.groupThreadRowId = groupThreadRowId
    }

    public init?(_ notification: NSNotification) {
        guard
            notification.name == Self.name,
            let callId = notification.userInfo?[UserInfoKeys.callId] as? UInt64,
            let groupThreadRowId = notification.userInfo?[UserInfoKeys.groupThreadRowId] as? Int64
        else {
            return nil
        }

        self.init(callId: callId, groupThreadRowId: groupThreadRowId)
    }

    var asNotification: Notification {
        Notification(
            name: Self.name,
            userInfo: [
                UserInfoKeys.callId: callId,
                UserInfoKeys.groupThreadRowId: groupThreadRowId
            ]
        )
    }
}
