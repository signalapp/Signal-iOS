//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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
        case newJoinRequestFromSingleUser(requestingAddress: SignalServiceAddress)
        case canceledJoinRequestFromSingleUser(cancelingAddress: SignalServiceAddress)
        case bannedMemberChange
        case invitedPnisPromotedToFullMemberAcis(promotions: [(pni: UntypedServiceId, aci: UntypedServiceId)])
        case invitesRemoved(invitees: [UntypedServiceId])

        /// Computes the matching group update type, if any.
        ///
        /// - Returns
        /// An update representing the "diff" of the given memberships. Returns
        /// `nil` if the diff does not exactly match exactly one update type.
        static func from(
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership,
            newlyLearnedPniToAciAssociations: [UntypedServiceId: UntypedServiceId]
        ) -> Self? {
            let membersDiff: Set<UUID> = newGroupMembership.allMemberUuidsOfAnyKind
                .symmetricDifference(oldGroupMembership.allMemberUuidsOfAnyKind)

            let bannedDiff: Set<UUID> = newGroupMembership.bannedMemberUuids
                .symmetricDifference(oldGroupMembership.bannedMemberUuids)

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
                return .newJoinRequestFromSingleUser(requestingAddress: SignalServiceAddress(uuid: newlyRequestingMember))
            } else if let canceledRequestingMember = checkForCanceledJoinRequestFromSingleUser(
                membersDiff: membersDiff,
                oldGroupMembership: oldGroupMembership,
                newGroupMembership: newGroupMembership
            ) {
                return .canceledJoinRequestFromSingleUser(cancelingAddress: SignalServiceAddress(uuid: canceledRequestingMember))
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
            membersDiff: Set<UUID>,
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership
        ) -> UUID? {
            guard membersDiff.count == 1, let changedMember = membersDiff.first else {
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
            membersDiff: Set<UUID>,
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership
        ) -> UUID? {
            guard membersDiff.count == 1, let changedMember = membersDiff.first else {
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
            membersDiff: Set<UUID>,
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership,
            newlyLearnedPniToAciAssociations: [UntypedServiceId: UntypedServiceId]
        ) -> [(pni: UntypedServiceId, aci: UntypedServiceId)]? {
            var remainingMembers = membersDiff
            var promotions: [(pni: UntypedServiceId, aci: UntypedServiceId)] = []

            for possiblyInvitedPni in membersDiff.map({ UntypedServiceId($0) }) {
                if
                    oldGroupMembership.isInvitedMember(possiblyInvitedPni.uuidValue),
                    let fullMemberAci = newlyLearnedPniToAciAssociations[possiblyInvitedPni],
                    newGroupMembership.isFullMember(fullMemberAci.uuidValue)
                {
                    remainingMembers.remove(possiblyInvitedPni.uuidValue)
                    remainingMembers.remove(fullMemberAci.uuidValue)

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
            membersDiff: Set<UUID>,
            oldGroupMembership: GroupMembership,
            newGroupMembership: GroupMembership
        ) -> [UntypedServiceId]? {
            var remainingMembers = membersDiff
            var removedInvites: [UntypedServiceId] = []

            for possiblyRemovedInvite in membersDiff.map({ UntypedServiceId($0) }) {
                if
                    oldGroupMembership.isInvitedMember(possiblyRemovedInvite.uuidValue),
                    !newGroupMembership.isMemberOfAnyKind(possiblyRemovedInvite.uuidValue)
                {
                    remainingMembers.remove(possiblyRemovedInvite.uuidValue)

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
