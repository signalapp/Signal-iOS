//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public indirect enum GroupUpdateSource {
    /// No source found.
    case unknown

    /// Source known to be the local user. The original source
    /// cannot itself be localUser or unknown.
    case localUser(originalSource: GroupUpdateSource)

    /// Legacy update (pre-GV2) with only an e164.
    case legacyE164(E164)

    /// Standard case. Most updates come from an ACI.
    case aci(Aci)

    /// A user who was invited by PNI rejected the invite.
    ///
    /// This case will refer to the ``GroupsProtoGroupChangeActionsDeletePendingMemberAction``,
    /// when the pending member in question is identified by a PNI.
    ///
    /// This is, at the time of writing, the only case in which the best
    /// identifier we have for the group update source is a PNI.
    case rejectedInviteToPni(Pni)

    /// If future updates introduce additional cases in which a PNI is the
    /// best/only identifier for the group update source, add them here. These
    /// cases are rare exceptions to the rule, so we prefer to enumerate them so
    /// as to make it easier for callers to understand exactly when they might
    /// be dealing with a PNI.
}

extension GroupUpdateSource {

    public func serviceIdUnsafeForLocalUserComparison() -> ServiceId? {
        switch self {
        case .unknown:
            return nil
        case .legacyE164:
            return nil
        case .aci(let aci):
            return aci
        case .rejectedInviteToPni(let pni):
            return pni
        case .localUser(let originalSource):
            return originalSource.serviceIdUnsafeForLocalUserComparison()
        }
    }
}

extension GroupUpdateSource: Equatable {}

extension TSInfoMessage {

    // MARK: - Serialization

    internal static func legacyGroupUpdateSource(
        infoMessageUserInfoDict: [InfoMessageUserInfoKey: Any]?
    ) -> GroupUpdateSource {
        guard let infoMessageUserInfoDict else {
            return .unknown
        }

        // Legacy cases stored if they were known local users.
        let isKnownLocalUser: () -> Bool = {
            if let storedValue = infoMessageUserInfoDict[.legacyUpdaterKnownToBeLocalUser] as? Bool {
                return storedValue
            }

            // Check for legacy persisted enum state.
            if
                let legacyPrecomputed = infoMessageUserInfoDict[.legacyGroupUpdateItems]
                    as? LegacyPersistableGroupUpdateItemsWrapper,
                case let .inviteRemoved(_, wasLocalUser) = legacyPrecomputed.updateItems.first
            {
                return wasLocalUser
            }
            return false
        }

        guard let address = infoMessageUserInfoDict[.groupUpdateSourceLegacyAddress] as? SignalServiceAddress else {
            return .unknown
        }
        if let aci = address.serviceId as? Aci {
            if isKnownLocalUser() {
                return .localUser(originalSource: .aci(aci))
            }
            return .aci(aci)
        } else if let pni = address.serviceId as? Pni {
            // When GroupUpdateSource was introduced, the _only_ way to have
            // a Pni (and not an aci) be the source address was when the update
            // came from someone invited by Pni rejecting that invitation.
            // Maybe other cases got added in the future, but if they did they'd
            // not use the legacy address storage, so if we find a legacy address
            // with a Pni, it _must_ be from the pni invite rejection case.
            if isKnownLocalUser() {
                return .localUser(originalSource: .rejectedInviteToPni(pni))
            } else {
                return .rejectedInviteToPni(pni)
            }
        } else if let e164 = address.e164 {
            if isKnownLocalUser() {
                return .localUser(originalSource: .legacyE164(e164))
            } else {
                return .legacyE164(e164)
            }
        } else {
            return .unknown
        }
    }
}
