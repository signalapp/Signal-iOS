//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum GroupUpdateSource {
    /// No source found.
    case unknown
    /// Legacy update (pre-gv2) with only an e164.
    case legacyE164(E164)
    /// Standard case. Most updates come from an aci.
    case aci(Aci)
    /// Only case at time of writing where an update comes
    /// from a pni; a user invited by pni rejected that invite.
    case rejectedInviteToPni(Pni)

    // If there are new cases where updates are authored by
    // a pni, add them here. This is because pni authors are
    // the SUPER rare exception to the rule, and forcing
    // every other case to wonder "when is this a Pni?" is
    // more onerous than explicitly typing all such cases.
}

extension GroupUpdateSource {

    public func serviceId() -> ServiceId? {
        switch self {
        case .unknown:
            return nil
        case .legacyE164:
            return nil
        case .aci(let aci):
            return aci
        case .rejectedInviteToPni(let pni):
            return pni
        }
    }
}

extension GroupUpdateSource: Equatable {}

extension TSInfoMessage {

    // MARK: - Serialization

    private enum GroupUpdateSourceRaw: Int {
        /// Historically we serialized the updater as a SignalServiceAddress,
        /// so it could be an e164, aci, pni, or unknown.
        /// If it is a pni, it _must_ be from an update
        /// where a pni invitee rejected the invite. All other
        /// cases use aci, or were created after the introduction
        /// of this type and therefore would not use the legacy case.
        case legacy = 0
        case aci = 1
        case rejectedInviteToPni = 2
    }

    internal static func insertGroupUpdateSource(
        _ groupUpdateSource: GroupUpdateSource,
        intoInfoMessageUserInfoDict userInfoDict: inout [InfoMessageUserInfoKey: Any],
        localIdentifiers: LocalIdentifiers
    ) {
        switch groupUpdateSource {
        case .unknown:
            // Don't insert anything.
            return
        case .legacyE164(let e164):
            // We really shouldn't be inserting these in the modern day...
            owsFailDebug("Serializing e164 group updater!")
            userInfoDict[.groupUpdateSourceType] = GroupUpdateSourceRaw.legacy.rawValue
            userInfoDict[.groupUpdateSourceLegacyAddress] = SignalServiceAddress(e164)
            userInfoDict[.legacyUpdaterKnownToBeLocalUser] = localIdentifiers.contains(phoneNumber: e164)
        case .aci(let aci):
            userInfoDict[.groupUpdateSourceType] = GroupUpdateSourceRaw.aci.rawValue
            userInfoDict[.groupUpdateSourceAciData] = Data(aci.serviceIdBinary)
        case .rejectedInviteToPni(let pni):
            userInfoDict[.groupUpdateSourceType] = GroupUpdateSourceRaw.rejectedInviteToPni.rawValue
            userInfoDict[.groupUpdateSourcePniData] = Data(pni.serviceIdBinary)
        }
    }

    internal static func groupUpdateSource(
        infoMessageUserInfoDict: [InfoMessageUserInfoKey: Any]?
    ) -> GroupUpdateSource {
        guard let infoMessageUserInfoDict else {
            return .unknown
        }

        guard let rawType = infoMessageUserInfoDict[.groupUpdateSourceType] as? Int else {
            return legacyGroupUpdateSource(infoMessageUserInfoDict: infoMessageUserInfoDict)
        }
        switch GroupUpdateSourceRaw(rawValue: rawType) {
        case .none:
            owsFailDebug("Unknown group update source")
            return legacyGroupUpdateSource(infoMessageUserInfoDict: infoMessageUserInfoDict)
        case .legacy:
            return legacyGroupUpdateSource(infoMessageUserInfoDict: infoMessageUserInfoDict)
        case .aci:
            guard
                let aciData = infoMessageUserInfoDict[.groupUpdateSourceAciData] as? Data,
                let aci = try? Aci.parseFrom(serviceIdBinary: aciData)
            else {
                return .unknown
            }
            return .aci(aci)
        case .rejectedInviteToPni:
            guard
                let pniData = infoMessageUserInfoDict[.groupUpdateSourcePniData] as? Data,
                let pni = try? Pni.parseFrom(serviceIdBinary: pniData)
            else {
                return .unknown
            }
            return .rejectedInviteToPni(pni)
        }
    }

    private static func legacyGroupUpdateSource(
        infoMessageUserInfoDict: [InfoMessageUserInfoKey: Any]
    ) -> GroupUpdateSource {
        guard let address = infoMessageUserInfoDict[.groupUpdateSourceLegacyAddress] as? SignalServiceAddress else {
            return .unknown
        }
        if let aci = address.serviceId as? Aci {
            return .aci(aci)
        } else if let pni = address.serviceId as? Pni {
            // When GroupUpdateSource was introduced, the _only_ way to have
            // a Pni (and not an aci) be the source address was when the update
            // came from someone invited by Pni rejecting that invitation.
            // Maybe other cases got added in the future, but if they did they'd
            // not use the legacy address storage, so if we find a legacy address
            // with a Pni, it _must_ be from the pni invite rejection case.
            return .rejectedInviteToPni(pni)
        } else if let e164 = address.e164 {
            return .legacyE164(e164)
        } else {
            return .unknown
        }
    }
}
