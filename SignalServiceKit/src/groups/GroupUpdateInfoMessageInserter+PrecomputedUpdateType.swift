//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension GroupUpdateInfoMessageInserterImpl {
    /// Most group updates are computed via presentation-time "diffing" of group
    /// model objects stored wholesale on an info message. This type represents
    /// the group updates whose "diff" is "precomputed" and stored on the info
    /// message such that presentation-time diffing is unnecessary.
    ///
    /// At present, precomputed group updates are necessary for updates that
    /// cannot be inferred purely from a diff of the group models, or that
    /// require updating existing info message state.
    ///
    /// An eventual goal of this type is that *all* group updates will be
    /// precomputed, obviating the need for presentation-time diffing at all
    /// (outside legacy data).
    enum PrecomputedUpdateType {
        case newJoinRequestFromSingleUser(requestingAci: Aci)
        case canceledJoinRequestFromSingleUser(cancelingAci: Aci)
        case bannedMemberChange
        case invitedPnisPromotedToFullMemberAcis(promotions: [(pni: Pni, aci: Aci)])
        case invitesRemoved(invitees: [ServiceId])

        /// Computes the matching group update type, if any.
        ///
        /// - Returns
        /// An update representing the "diff" of the given memberships. Returns
        /// `nil` if the diff does not exactly match exactly one update type.
        static func from(
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership,
            newlyLearnedPniToAciAssociations: [Pni: Aci]
        ) -> Self? {
            let membersDiff: Set<ServiceId> = newGroupMembership.allMembersOfAnyKindServiceIds
                .symmetricDifference(oldGroupMembership.allMembersOfAnyKindServiceIds)

            let bannedDiff: Set<Aci> = Set(newGroupMembership.bannedMembers.keys)
                .symmetricDifference(oldGroupMembership.bannedMembers.keys)

            if
                membersDiff.isEmpty,
                !bannedDiff.isEmpty
            {
                return .bannedMemberChange
            } else if let newlyRequestingMember = checkForNewJoinRequestFromSingleUser(
                membersDiff: membersDiff,
                oldGroupMembership: oldGroupMembership,
                newGroupMembership: newGroupMembership
            ) {
                return .newJoinRequestFromSingleUser(requestingAci: newlyRequestingMember)
            } else if let canceledRequestingMember = checkForCanceledJoinRequestFromSingleUser(
                membersDiff: membersDiff,
                oldGroupMembership: oldGroupMembership,
                newGroupMembership: newGroupMembership
            ) {
                return .canceledJoinRequestFromSingleUser(cancelingAci: canceledRequestingMember)
            } else if let pniToAciPromotions = checkForInvitedPniPromotions(
                membersDiff: membersDiff,
                oldGroupMembership: oldGroupMembership,
                newGroupMembership: newGroupMembership,
                newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations
            ) {
                return .invitedPnisPromotedToFullMemberAcis(promotions: pniToAciPromotions)
            } else if let removedInvites = checkForRemovedInvites(
                membersDiff: membersDiff,
                oldGroupMembership: oldGroupMembership,
                newGroupMembership: newGroupMembership
            ) {
                return .invitesRemoved(invitees: removedInvites)
            } else {
                return nil
            }
        }

        /// Check the given members diff to see if the entire diff can be
        /// explained by a new join request from a single user.
        /// - Returns
        /// The requesting user's ID, if they constitute the entire given diff.
        /// Otherwise, returns `nil`.
        private static func checkForNewJoinRequestFromSingleUser(
            membersDiff: Set<ServiceId>,
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership
        ) -> Aci? {
            guard membersDiff.count == 1, let changedMember = membersDiff.first as? Aci else {
                return nil
            }

            if
                !oldGroupMembership.isMemberOfAnyKind(changedMember),
                newGroupMembership.isRequestingMember(changedMember)
            {
                return changedMember
            }

            return nil
        }

        /// Check the given members diff to see if the entire diff can be
        /// explained by a canceled join request from a single user.
        /// - Returns
        /// The requesting user's ID, if they constitute the entire given diff.
        /// Otherwise, returns `nil`.
        private static func checkForCanceledJoinRequestFromSingleUser(
            membersDiff: Set<ServiceId>,
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership
        ) -> Aci? {
            guard membersDiff.count == 1, let changedMember = membersDiff.first as? Aci else {
                return nil
            }

            if
                oldGroupMembership.isRequestingMember(changedMember),
                !newGroupMembership.isMemberOfAnyKind(changedMember)
            {
                return changedMember
            }

            return nil
        }

        /// Check the given members diff to see if the entire diff can be
        /// explained by promotions of invited PNIs to full-member ACIs.
        /// - Returns
        /// The promoted PNI -> ACI pairs, if they constitute the entire given
        /// diff. Otherwise, returns `nil`.
        private static func checkForInvitedPniPromotions(
            membersDiff: Set<ServiceId>,
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership,
            newlyLearnedPniToAciAssociations: [Pni: Aci]
        ) -> [(pni: Pni, aci: Aci)]? {
            var remainingMembers = membersDiff
            var promotions: [(pni: Pni, aci: Aci)] = []

            for possiblyInvitedPni in membersDiff.compactMap({ $0 as? Pni }) {
                if
                    oldGroupMembership.isInvitedMember(possiblyInvitedPni),
                    let fullMemberAci = newlyLearnedPniToAciAssociations[possiblyInvitedPni],
                    newGroupMembership.isFullMember(fullMemberAci)
                {
                    remainingMembers.remove(possiblyInvitedPni)
                    remainingMembers.remove(fullMemberAci)

                    promotions.append((pni: possiblyInvitedPni, aci: fullMemberAci))
                }
            }

            if remainingMembers.isEmpty {
                return promotions
            }

            return nil
        }

        /// Check the given memberes diff to see if the entire diff can be
        /// explained by removed (declined or revoked) invites.
        /// - Returns
        /// The IDs of the users whose invites were removed, if they constitute
        /// the entire given diff. Otherwise, returns `nil`.
        private static func checkForRemovedInvites(
            membersDiff: Set<ServiceId>,
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership
        ) -> [ServiceId]? {
            var remainingMembers = membersDiff
            var removedInvites: [ServiceId] = []

            for possiblyRemovedInvite in membersDiff {
                if
                    oldGroupMembership.isInvitedMember(possiblyRemovedInvite),
                    !newGroupMembership.isMemberOfAnyKind(possiblyRemovedInvite)
                {
                    remainingMembers.remove(possiblyRemovedInvite)

                    removedInvites.append(possiblyRemovedInvite)
                }
            }

            if remainingMembers.isEmpty {
                return removedInvites
            }

            return nil
        }
    }
}
