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

    /// Update the joined members and creator of a group call on the associated
    /// group-call interaction.
    func updateGroupCallInteractionAcis(
        groupCallInteraction: OWSGroupCallMessage,
        joinedMemberAcis: [Aci],
        creatorAci: Aci,
        tx: DBWriteTransaction
    ) {
        updateInteraction(groupCallInteraction, tx: tx) { groupCallInteraction in
            groupCallInteraction.hasEnded = joinedMemberAcis.isEmpty
            groupCallInteraction.creatorUuid = creatorAci.serviceIdUppercaseString
            groupCallInteraction.joinedMemberUuids = joinedMemberAcis.map { $0.serviceIdUppercaseString }
        }
    }
}
