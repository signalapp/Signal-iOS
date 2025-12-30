//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

// MARK: - GroupMemberState

private enum GroupMemberState: Equatable, Codable, CustomStringConvertible {
    case fullMember(
        role: TSGroupMemberRole,
        didJoinFromInviteLink: Bool,
        didJoinFromAcceptedJoinRequest: Bool,
    )
    case invited(role: TSGroupMemberRole, addedByAci: Aci)
    case requesting

    var role: TSGroupMemberRole {
        switch self {
        case .fullMember(let role, _, _):
            return role
        case .invited(let role, _):
            return role
        case .requesting:
            return .`normal`
        }
    }

    var isAdministrator: Bool {
        role == .administrator
    }

    var isFullMember: Bool {
        switch self {
        case .fullMember: return true
        default: return false
        }
    }

    var isInvited: Bool {
        switch self {
        case .invited: return true
        default: return false
        }
    }

    var isRequesting: Bool {
        switch self {
        case .requesting: return true
        default: return false
        }
    }

    // MARK: -

    private enum TypeKey: UInt, Codable {
        case fullMember = 0
        case invited = 1
        case requesting = 2
    }

    private enum CodingKeys: String, CodingKey {
        case typeKey
        case role
        case addedByAci = "addedByUuid"
        case didJoinFromInviteLink
        case didJoinFromAcceptedJoinRequest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let typeKey = try container.decode(TypeKey.self, forKey: .typeKey)
        switch typeKey {
        case .fullMember:
            let role = try container.decode(TSGroupMemberRole.self, forKey: .role)
            let didJoinFromInviteLink = try container.decodeIfPresent(Bool.self, forKey: .didJoinFromInviteLink) ?? false
            let didJoinFromAcceptedJoinRequest = try container.decodeIfPresent(
                Bool.self,
                forKey: .didJoinFromAcceptedJoinRequest,
            ) ?? false
            self = .fullMember(
                role: role,
                didJoinFromInviteLink: didJoinFromInviteLink,
                didJoinFromAcceptedJoinRequest: didJoinFromAcceptedJoinRequest,
            )
        case .invited:
            let role = try container.decode(TSGroupMemberRole.self, forKey: .role)
            let addedByAci = try container.decode(UUID.self, forKey: .addedByAci)
            self = .invited(role: role, addedByAci: Aci(fromUUID: addedByAci))
        case .requesting:
            self = .requesting
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .fullMember(let role, let didJoinFromInviteLink, let didJoinFromAcceptedJoinRequest):
            try container.encode(TypeKey.fullMember, forKey: .typeKey)
            try container.encode(role, forKey: .role)
            try container.encode(didJoinFromInviteLink, forKey: .didJoinFromInviteLink)
            try container.encode(
                didJoinFromAcceptedJoinRequest,
                forKey: .didJoinFromAcceptedJoinRequest,
            )
        case .invited(let role, let addedByAci):
            try container.encode(TypeKey.invited, forKey: .typeKey)
            try container.encode(role, forKey: .role)
            try container.encode(addedByAci.rawUUID, forKey: .addedByAci)
        case .requesting:
            try container.encode(TypeKey.requesting, forKey: .typeKey)
        }
    }

    // MARK: -

    var description: String {
        switch self {
        case .fullMember: return ".fullMember"
        case .invited: return ".invited"
        case .requesting: return ".requesting"
        }
    }
}

// MARK: -

@objc
public class GroupMembership: NSObject, NSCoding {

    // MARK: Types

    public typealias BannedAtTimestampMillis = UInt64
    public typealias BannedMembersMap = [Aci: BannedAtTimestampMillis]

    fileprivate typealias MemberStateMap = [SignalServiceAddress: GroupMemberState]
    fileprivate typealias InvalidInviteMap = [Data: InvalidInviteModel]

    private typealias LegacyMemberStateMap = [SignalServiceAddress: LegacyMemberState]

    // MARK: Init

    fileprivate var memberStates: MemberStateMap
    public fileprivate(set) var bannedMembers: BannedMembersMap
    private var invalidInviteMap: InvalidInviteMap

    public var invalidInviteUserIds: [Data] {
        return Array(invalidInviteMap.keys)
    }

    @objc
    override public init() {
        self.memberStates = [:]
        self.bannedMembers = [:]
        self.invalidInviteMap = [:]

        super.init()
    }

    @objc
    public required init?(coder aDecoder: NSCoder) {
        if let invalidInviteMap = aDecoder.decodeObject(forKey: Self.invalidInviteMapKey) as? InvalidInviteMap {
            self.invalidInviteMap = invalidInviteMap
        } else {
            // invalidInviteMap is optional.
            self.invalidInviteMap = [:]
        }

        if let memberStatesData = aDecoder.decodeObject(forKey: Self.memberStatesKey) as? Data {
            let decoder = JSONDecoder()
            do {
                self.memberStates = try decoder.decode(MemberStateMap.self, from: memberStatesData)
            } catch {
                owsFailDebug("Could not decode member states: \(error)")
                return nil
            }
        } else if let legacyMemberStateMap = aDecoder.decodeObject(forKey: Self.legacyMemberStatesKey) as? LegacyMemberStateMap {
            self.memberStates = Self.convertLegacyMemberStateMap(legacyMemberStateMap)
        } else {
            owsFailDebug("Could not decode legacy member states.")
            return nil
        }

        if let bannedMembers = aDecoder.decodeObject(forKey: Self.bannedMembersKey) as? [UUID: BannedAtTimestampMillis] {
            self.bannedMembers = bannedMembers.mapKeys(injectiveTransform: { Aci(fromUUID: $0) })
        } else {
            // TODO: (Group Abuse) we should debug assert here eventually.
            // However, while clients are learning about banned members this is
            // a normal path to hit.
            self.bannedMembers = [:]
        }

        super.init()
    }

    private static var memberStatesKey: String { "memberStates" }
    private static var legacyMemberStatesKey: String { "memberStateMap" }
    private static var bannedMembersKey: String { "bannedMembers" }
    private static var invalidInviteMapKey: String { "invalidInviteMap" }

    public func encode(with aCoder: NSCoder) {
        let encoder = JSONEncoder()
        do {
            let memberStatesData = try encoder.encode(self.memberStates)
            aCoder.encode(memberStatesData, forKey: Self.memberStatesKey)
        } catch {
            owsFailDebug("Error: \(error)")
        }

        aCoder.encode(bannedMembers.mapKeys(injectiveTransform: { $0.rawUUID }), forKey: Self.bannedMembersKey)
        aCoder.encode(invalidInviteMap, forKey: Self.invalidInviteMapKey)
    }

    fileprivate init(
        memberStates: MemberStateMap,
        bannedMembers: BannedMembersMap,
        invalidInviteMap: InvalidInviteMap,
    ) {
        self.memberStates = memberStates
        self.bannedMembers = bannedMembers
        self.invalidInviteMap = invalidInviteMap

        super.init()
    }

    @objc
    init(v1Members: [SignalServiceAddress]) {
        var builder = Builder()
        builder.addFullMembers(Set(v1Members), role: .normal)
        self.memberStates = builder.memberStates
        self.bannedMembers = [:]
        self.invalidInviteMap = [:]

        super.init()
    }

#if TESTABLE_BUILD
    /// Construction for tests is functionally equivalent to construction of a
    /// group membership for a legacy, V1 group model.
    public convenience init(membersForTest: [SignalServiceAddress]) {
        self.init(v1Members: membersForTest)
    }
#endif

    // MARK: - Equality

    @objc
    override public func isEqual(_ object: Any!) -> Bool {
        guard let other = object as? GroupMembership else {
            return false
        }

        guard
            Self.memberStates(
                self.memberStates,
                areEqualTo: other.memberStates,
            )
        else {
            return false
        }

        guard self.bannedMembers == other.bannedMembers else {
            return false
        }

        let invalidlyInvitedUserIdsSet = Set(invalidInviteUserIds)
        let otherInvalidlyInvitedUserIdsSet = Set(other.invalidInviteUserIds)
        return invalidlyInvitedUserIdsSet == otherInvalidlyInvitedUserIdsSet
    }

    /// When comparing member states, ignore the ``didJoinFromInviteLink`` and
    /// ``didJoinFromAcceptedJoinRequest`` fields.
    /// These fields are not stored as part of memberships in group snapshots from
    /// the service, and are only computed when a member joins a group and we add
    /// them locally. If our local membership differs from a group snapshot's
    /// only in these fields, we want to consider them equal to avoid clobbering our local state.
    private static func memberStates(
        _ memberStates: MemberStateMap,
        areEqualTo otherMemberStates: MemberStateMap,
    ) -> Bool {

        func hardcodeDidJoinViaInviteLink(for groupMemberState: GroupMemberState) -> GroupMemberState {
            switch groupMemberState {
            case .fullMember(let role, _, _):
                return .fullMember(
                    role: role,
                    didJoinFromInviteLink: false,
                    didJoinFromAcceptedJoinRequest: false,
                )
            default:
                return groupMemberState
            }
        }

        guard memberStates.count == otherMemberStates.count else {
            return false
        }

        return memberStates.allSatisfy { key, value -> Bool in
            guard let otherValue = otherMemberStates[key] else { return false }
            return hardcodeDidJoinViaInviteLink(for: value) == hardcodeDidJoinViaInviteLink(for: otherValue)
        }
    }

    // MARK: -

    private static func convertLegacyMemberStateMap(_ legacyMemberStateMap: LegacyMemberStateMap) -> MemberStateMap {
        var result = MemberStateMap()
        for (address, legacyMemberState) in legacyMemberStateMap {
            let memberState: GroupMemberState
            if legacyMemberState.isPending {
                if let addedByUuid = legacyMemberState.addedByUuid {
                    memberState = .invited(role: legacyMemberState.role, addedByAci: Aci(fromUUID: addedByUuid))
                } else {
                    owsFailDebug("Missing addedByUuid.")
                    continue
                }
            } else {
                memberState = .fullMember(
                    role: legacyMemberState.role,
                    didJoinFromInviteLink: false,
                    didJoinFromAcceptedJoinRequest: false,
                )
            }
            result[address] = memberState
        }
        return result
    }

    // MARK: -

    public static var empty: GroupMembership {
        return Builder().build()
    }

    public var asBuilder: Builder {
        return Builder(
            memberStates: memberStates,
            bannedMembers: bannedMembers,
            invalidInviteMap: invalidInviteMap,
        )
    }

    override public var debugDescription: String {
        var result = "[\n"
        for address in allMembersOfAnyKind.sorted(by: { ($0.serviceId?.serviceIdString ?? "") < ($1.serviceId?.serviceIdString ?? "") }) {
            guard let memberState = memberStates[address] else {
                owsFailDebug("Missing memberState.")
                continue
            }
            result += "\(address), memberType: \(memberState)\n"
        }
        for (aci, bannedAtTimestamp) in bannedMembers {
            result += "Banned: \(aci), at \(bannedAtTimestamp)\n"
        }
        result += "]"
        return result
    }

    // MARK: -

    public var allMembersOfAnyKind: Set<SignalServiceAddress> {
        return Set(memberStates.keys)
    }

    public var allMembersOfAnyKindServiceIds: Set<ServiceId> {
        return Set(memberStates.keys.lazy.compactMap { $0.serviceId })
    }

    public func isMemberOfAnyKind(_ address: SignalServiceAddress) -> Bool {
        return memberStates[address] != nil
    }

    public func isMemberOfAnyKind(_ serviceId: ServiceId) -> Bool {
        return isMemberOfAnyKind(SignalServiceAddress(serviceId))
    }

    // MARK: -

    public func role(for serviceId: ServiceId) -> TSGroupMemberRole? {
        return role(for: SignalServiceAddress(serviceId))
    }

    public func role(for address: SignalServiceAddress) -> TSGroupMemberRole? {
        guard let memberState = memberStates[address] else {
            return nil
        }
        return memberState.role
    }

    // MARK: -

    public var fullMemberAdministrators: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter { $0.value.isAdministrator && $0.value.isFullMember }.map { $0.key })
    }

    public var fullMembers: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter { $0.value.isFullMember }.map { $0.key })
    }

    public func isFullMemberAndAdministrator(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isAdministrator && memberState.isFullMember
    }

    public func isFullMemberAndAdministrator(_ serviceId: ServiceId) -> Bool {
        return isFullMemberAndAdministrator(SignalServiceAddress(serviceId))
    }

    @objc
    public func isFullMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isFullMember
    }

    public func isFullMember(_ serviceId: ServiceId) -> Bool {
        return isFullMember(SignalServiceAddress(serviceId))
    }

    /// This method should only be called for full members.
    public func didJoinFromInviteLink(forFullMember address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            owsFailDebug("Missing member: \(address)")
            return false
        }
        switch memberState {
        case .fullMember(_, let didJoinFromInviteLink, _):
            return didJoinFromInviteLink
        default:
            owsFailDebug("Not a full member.")
            return false
        }
    }

    /// this method should only be called for full members.
    public func didJoinFromAcceptedJoinRequest(forFullMember address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            owsFailDebug("Missing member: \(address)")
            return false
        }
        switch memberState {
        case .fullMember(_, _, let didJoinFromAcceptedJoinRequest):
            return didJoinFromAcceptedJoinRequest
        default:
            owsFailDebug("Not a full member.")
            return false
        }
    }

    // MARK: -

    public var invitedMembers: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter { $0.value.isInvited }.map { $0.key })
    }

    public func isInvitedMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isInvited
    }

    public func isInvitedMember(_ serviceId: ServiceId) -> Bool {
        return isInvitedMember(SignalServiceAddress(serviceId))
    }

    /// This method should only be called on invited members.
    public func addedByAci(forInvitedMember address: SignalServiceAddress) -> Aci? {
        guard let memberState = memberStates[address] else {
            return nil
        }
        switch memberState {
        case .invited(_, let addedByAci):
            return addedByAci
        default:
            owsFailDebug("Not a pending profile key member.")
            return nil
        }
    }

    public func addedByAci(forInvitedMember serviceId: ServiceId) -> Aci? {
        return addedByAci(forInvitedMember: SignalServiceAddress(serviceId))
    }

    // MARK: -

    public var requestingMembers: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter { $0.value.isRequesting }.map { $0.key })
    }

    public func isRequestingMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isRequesting
    }

    public func isRequestingMember(_ serviceId: ServiceId) -> Bool {
        return isRequestingMember(SignalServiceAddress(serviceId))
    }

    // MARK: -

    public func isBannedMember(_ aci: Aci) -> Bool {
        return bannedMembers[aci] != nil
    }

    public func hasInvalidInvite(forUserId userId: Data) -> Bool {
        return invalidInviteMap[userId] != nil
    }

    // MARK: -

    /// Is this user's profile key exposed to the group?
    public func hasProfileKeyInGroup(serviceId: ServiceId) -> Bool {
        guard let memberState = memberStates[SignalServiceAddress(serviceId)] else {
            return false
        }

        switch memberState {
        case .fullMember, .requesting:
            return true
        case .invited:
            return false
        }
    }

    /// Can this user view the profile keys in the group?
    public func canViewProfileKeys(serviceId: ServiceId) -> Bool {
        guard let memberState = memberStates[SignalServiceAddress(serviceId)] else {
            return false
        }

        switch memberState {
        case .fullMember, .invited:
            return true
        case .requesting:
            return false
        }
    }

    // MARK: -

    public enum AddableResult {
        case alreadyInGroup
        case addableWithProfileKeyCredential
        case addableOrInvitable
    }

    public func canTryToAddToGroup(serviceId: ServiceId) -> AddableResult {
        if self.isFullMember(serviceId) {
            return .alreadyInGroup
        }
        if self.isRequestingMember(serviceId) {
            return .addableOrInvitable
        }
        if self.isInvitedMember(serviceId) {
            return .addableWithProfileKeyCredential
        }
        return .addableOrInvitable
    }

    public static func canTryToAddWithProfileKeyCredential(
        serviceId: ServiceId,
        groupsV2: any GroupsV2 = SSKEnvironment.shared.groupsV2Ref,
        profileManager: any ProfileManager = SSKEnvironment.shared.profileManagerRef,
        tsAccountManager: any TSAccountManager = DependenciesBridge.shared.tsAccountManager,
        udManager: any OWSUDManager = SSKEnvironment.shared.udManagerRef,
        tx: DBReadTransaction,
    ) -> Bool {
        // We can add invited members if we have...
        if let aci = serviceId as? Aci, groupsV2.hasProfileKeyCredential(for: aci, transaction: tx) {
            return true
        }
        // ...or can get a credential for them.
        return ProfileFetcherJob.canTryToFetchCredential(
            serviceId: serviceId,
            localIdentifiers: tsAccountManager.localIdentifiers(tx: tx)!,
            profileManager: profileManager,
            udManager: udManager,
            tx: tx,
        )
    }

    // MARK: - Builder

    public struct Builder {
        fileprivate var memberStates = MemberStateMap()
        private var bannedMembers = BannedMembersMap()
        private var invalidInviteMap = InvalidInviteMap()

        public init() {}

        fileprivate init(
            memberStates: MemberStateMap,
            bannedMembers: BannedMembersMap,
            invalidInviteMap: InvalidInviteMap,
        ) {
            self.memberStates = memberStates
            self.bannedMembers = bannedMembers
            self.invalidInviteMap = invalidInviteMap
        }

        // MARK: Member states

        public mutating func remove(_ serviceId: ServiceId) {
            remove(SignalServiceAddress(serviceId))
        }

        public mutating func remove(_ address: SignalServiceAddress) {
            remove([address])
        }

        public mutating func remove(_ addresses: Set<SignalServiceAddress>) {
            for address in addresses {
                memberStates.removeValue(forKey: address)
            }
        }

        public mutating func addFullMember(
            _ aci: Aci,
            role: TSGroupMemberRole,
            didJoinFromInviteLink: Bool = false,
            didJoinFromAcceptedJoinRequest: Bool = false,
        ) {
            addFullMember(
                SignalServiceAddress(aci),
                role: role,
                didJoinFromInviteLink: didJoinFromInviteLink,
                didJoinFromAcceptedJoinRequest: didJoinFromAcceptedJoinRequest,
            )
        }

        public mutating func addFullMember(
            _ address: SignalServiceAddress,
            role: TSGroupMemberRole,
            didJoinFromInviteLink: Bool = false,
            didJoinFromAcceptedJoinRequest: Bool = false,
        ) {
            addFullMembers(
                [address],
                role: role,
                didJoinFromInviteLink: didJoinFromInviteLink,
                didJoinFromAcceptedJoinRequest: didJoinFromAcceptedJoinRequest,
            )
        }

        public mutating func addFullMembers(
            _ addresses: Set<SignalServiceAddress>,
            role: TSGroupMemberRole,
            didJoinFromInviteLink: Bool = false,
            didJoinFromAcceptedJoinRequest: Bool = false,
        ) {
            // Dupe is not necessarily an error; you might know of the UUID
            // mapping for a user that another group member doesn't know about.
            addMembers(
                addresses,
                withState: .fullMember(
                    role: role,
                    didJoinFromInviteLink: didJoinFromInviteLink,
                    didJoinFromAcceptedJoinRequest: didJoinFromAcceptedJoinRequest,
                ),
                failOnDupe: false,
            )
        }

        public mutating func addInvitedMember(_ serviceId: ServiceId, role: TSGroupMemberRole, addedByAci: Aci) {
            addInvitedMember(SignalServiceAddress(serviceId), role: role, addedByAci: addedByAci)
        }

        public mutating func addInvitedMember(
            _ address: SignalServiceAddress,
            role: TSGroupMemberRole,
            addedByAci: Aci,
        ) {
            addInvitedMembers([address], role: role, addedByAci: addedByAci)
        }

        public mutating func addInvitedMembers(
            _ addresses: Set<SignalServiceAddress>,
            role: TSGroupMemberRole,
            addedByAci: Aci,
        ) {
            addMembers(addresses, withState: .invited(role: role, addedByAci: addedByAci))
        }

        public mutating func addRequestingMember(_ aci: Aci) {
            addRequestingMember(SignalServiceAddress(aci))
        }

        public mutating func addRequestingMember(_ address: SignalServiceAddress) {
            addRequestingMembers([address])
        }

        public mutating func addRequestingMembers(_ addresses: Set<SignalServiceAddress>) {
            addMembers(addresses, withState: .requesting)
        }

        private mutating func addMembers(
            _ addresses: Set<SignalServiceAddress>,
            withState memberState: GroupMemberState,
            failOnDupe: Bool = true,
        ) {
            for address in addresses {
                guard memberStates[address] == nil else {
                    let errorMessage = "Duplicate address."
                    if failOnDupe {
                        owsFailDebug(errorMessage)
                    } else {
                        Logger.warn(errorMessage)
                    }
                    continue
                }

                memberStates[address] = memberState
            }
        }

        public func hasMemberOfAnyKind(_ address: SignalServiceAddress) -> Bool {
            nil != memberStates[address]
        }

        // MARK: Banned members

        public mutating func addBannedMember(_ aci: Aci, bannedAtTimestamp: BannedAtTimestampMillis) {
            guard bannedMembers[aci] == nil else {
                owsFailDebug("Duplicate banned member!")
                return
            }

            bannedMembers[aci] = bannedAtTimestamp
        }

        public mutating func removeBannedMember(_ aci: Aci) {
            guard bannedMembers[aci] != nil else {
                owsFailDebug("Removing not-currently-banned member!")
                return
            }

            bannedMembers.removeValue(forKey: aci)
        }

        // MARK: Invalid invites

        public mutating func addInvalidInvite(userId: Data, addedByUserId: Data) {
            invalidInviteMap[userId] = InvalidInviteModel(userId: userId, addedByUserId: addedByUserId)
        }

        public mutating func removeInvalidInvite(userId: Data) {
            invalidInviteMap.removeValue(forKey: userId)
        }

        public func hasInvalidInvite(userId: Data) -> Bool {
            nil != invalidInviteMap[userId]
        }

        // MARK: Build

        public func build() -> GroupMembership {
            owsAssertDebug(Set(bannedMembers.keys.lazy.map { SignalServiceAddress($0) })
                .isDisjoint(with: Set(memberStates.keys)))

            // TODO: Why is this here? Uggh.
            let memberStates = self.memberStates.filter {
                $0.key.phoneNumber != OWSUserProfile.Constants.localProfilePhoneNumber
            }

            return GroupMembership(
                memberStates: memberStates,
                bannedMembers: bannedMembers,
                invalidInviteMap: invalidInviteMap,
            )
        }
    }

    // MARK: - Local user accessors

    /// The local PNI, if it is present and an invited member.
    ///
    /// - Note
    /// PNIs can only be invited members. Further note that profile keys are
    /// required for full and requesting members, and PNIs have no associated
    /// profile or profile key.
    private func localPniAsInvitedMember(localIdentifiers: LocalIdentifiers) -> Pni? {
        if let localPni = localIdentifiers.pni, isInvitedMember(localPni) {
            return localPni
        }

        return nil
    }

    public var isLocalUserMemberOfAnyKind: Bool {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            return false
        }

        if isMemberOfAnyKind(localIdentifiers.aciAddress) {
            return true
        }

        return localPniAsInvitedMember(localIdentifiers: localIdentifiers) != nil
    }

    public var isLocalUserFullMember: Bool {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            return false
        }

        return isFullMember(localAci)
    }

    /// The ID at which the local user is invited, if at all.
    ///
    /// Checks membership for the local ACI first. If none is available, falls
    /// back to checking membership for the local PNI.
    public func localUserInvitedAtServiceId(localIdentifiers: LocalIdentifiers) -> ServiceId? {
        if isMemberOfAnyKind(localIdentifiers.aci) {
            // If our ACI is any kind of member, return that membership rather
            // than falling back to the PNI.
            if isInvitedMember(localIdentifiers.aci) {
                return localIdentifiers.aci
            }

            return nil
        }

        return localPniAsInvitedMember(localIdentifiers: localIdentifiers)
    }

    /// Whether the local user is an invited member.
    ///
    /// Checks membership for the local ACI first. If none is available, falls
    /// back to checking membership for the local PNI.
    public var isLocalUserInvitedMember: Bool {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            return false
        }

        return localUserInvitedAtServiceId(localIdentifiers: localIdentifiers) != nil
    }

    public var isLocalUserRequestingMember: Bool {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            return false
        }

        return isRequestingMember(localAci)
    }

    public var isLocalUserFullOrInvitedMember: Bool {
        return isLocalUserFullMember || isLocalUserInvitedMember
    }

    public var isLocalUserFullMemberAndAdministrator: Bool {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            return false
        }

        return isFullMemberAndAdministrator(localAci)
    }
}

// MARK: - InvalidInviteModel

@objc(GroupMembershipInvalidInviteModel)
private final class InvalidInviteModel: NSObject, NSCoding, NSCopying {
    init?(coder: NSCoder) {
        self.addedByUserId = coder.decodeObject(of: NSData.self, forKey: "addedByUserId") as Data?
        self.userId = coder.decodeObject(of: NSData.self, forKey: "userId") as Data?
    }

    func encode(with coder: NSCoder) {
        if let addedByUserId {
            coder.encode(addedByUserId, forKey: "addedByUserId")
        }
        if let userId {
            coder.encode(userId, forKey: "userId")
        }
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(addedByUserId)
        hasher.combine(userId)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.addedByUserId == object.addedByUserId else { return false }
        guard self.userId == object.userId else { return false }
        return true
    }

    func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    let userId: Data?
    let addedByUserId: Data?

    init(userId: Data?, addedByUserId: Data? = nil) {
        self.userId = userId
        self.addedByUserId = addedByUserId
    }
}

// MARK: - LegacyMemberState

@objc(_TtCC16SignalServiceKit15GroupMembership11MemberState)
private final class LegacyMemberState: NSObject, NSCoding, NSCopying {
    init?(coder: NSCoder) {
        self.addedByUuid = coder.decodeObject(of: NSUUID.self, forKey: "addedByUuid") as UUID?
        self.isPending = coder.decodeObject(of: NSNumber.self, forKey: "isPending")?.boolValue ?? false
        self.role = (coder.decodeObject(of: NSNumber.self, forKey: "role")?.uintValue).flatMap(TSGroupMemberRole.init(rawValue:)) ?? .normal
    }

    func encode(with coder: NSCoder) {
        if let addedByUuid {
            coder.encode(addedByUuid, forKey: "addedByUuid")
        }
        coder.encode(NSNumber(value: self.isPending), forKey: "isPending")
        coder.encode(NSNumber(value: self.role.rawValue), forKey: "role")
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(addedByUuid)
        hasher.combine(isPending)
        hasher.combine(role)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.addedByUuid == object.addedByUuid else { return false }
        guard self.isPending == object.isPending else { return false }
        guard self.role == object.role else { return false }
        return true
    }

    func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    let role: TSGroupMemberRole
    let isPending: Bool
    // Only applies for pending members.
    let addedByUuid: UUID?

    init(role: TSGroupMemberRole, isPending: Bool, addedByUuid: UUID? = nil) {
        self.role = role
        self.isPending = isPending
        self.addedByUuid = addedByUuid
    }

    @objc
    var isAdministrator: Bool {
        return role == .administrator
    }
}
