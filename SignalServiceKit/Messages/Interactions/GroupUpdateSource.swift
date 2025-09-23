//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public indirect enum GroupUpdateSource: Equatable {
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
