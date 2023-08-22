//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// MARK: - GroupMemberState

private enum GroupMemberState: Equatable {
    case fullMember(role: TSGroupMemberRole, didJoinFromInviteLink: Bool)
    case invited(role: TSGroupMemberRole, addedByAci: Aci)
    case requesting

    var role: TSGroupMemberRole {
        switch self {
        case .fullMember(let role, _):
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
}

extension GroupMemberState: Codable {
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let typeKey = try container.decode(TypeKey.self, forKey: .typeKey)
        switch typeKey {
        case .fullMember:
            let role = try container.decode(TSGroupMemberRole.self, forKey: .role)
            let didJoinFromInviteLink = try container.decodeIfPresent(Bool.self, forKey: .didJoinFromInviteLink) ?? false
            self = .fullMember(role: role, didJoinFromInviteLink: didJoinFromInviteLink)
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
        case .fullMember(let role, let didJoinFromInviteLink):
            try container.encode(TypeKey.fullMember, forKey: .typeKey)
            try container.encode(role, forKey: .role)
            try container.encode(didJoinFromInviteLink, forKey: .didJoinFromInviteLink)
        case .invited(let role, let addedByAci):
            try container.encode(TypeKey.invited, forKey: .typeKey)
            try container.encode(role, forKey: .role)
            try container.encode(addedByAci.rawUUID, forKey: .addedByAci)
        case .requesting:
            try container.encode(TypeKey.requesting, forKey: .typeKey)
        }
    }
}

extension GroupMemberState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fullMember: return ".fullMember"
        case .invited: return ".invited"
        case .requesting: return ".requesting"
        }
    }
}

// MARK: -

@objc
public class GroupMembership: MTLModel {

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
    public override init() {
        self.memberStates = [:]
        self.bannedMembers = [:]
        self.invalidInviteMap = [:]

        super.init()
    }

    @objc
    required public init?(coder aDecoder: NSCoder) {
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

    public override func encode(with aCoder: NSCoder) {
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

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }

    fileprivate init(
        memberStates: MemberStateMap,
        bannedMembers: BannedMembersMap,
        invalidInviteMap: InvalidInviteMap
    ) {
        self.memberStates = memberStates
        self.bannedMembers = bannedMembers
        self.invalidInviteMap = invalidInviteMap

        super.init()
    }

    @objc
    public init(v1Members: Set<SignalServiceAddress>) {
        var builder = Builder()
        builder.addFullMembers(v1Members, role: .normal)
        self.memberStates = builder.memberStates
        self.bannedMembers = [:]
        self.invalidInviteMap = [:]

        super.init()
    }

    // MARK: - Equality

    @objc
    public override func isEqual(_ object: Any!) -> Bool {
        guard let other = object as? GroupMembership else {
            return false
        }

        guard Self.memberStates(
            self.memberStates,
            areEqualTo: other.memberStates
        ) else {
            return false
        }

        guard self.bannedMembers == other.bannedMembers else {
            return false
        }

        let invalidlyInvitedUserIdsSet = Set(invalidInviteUserIds)
        let otherInvalidlyInvitedUserIdsSet = Set(other.invalidInviteUserIds)
        return invalidlyInvitedUserIdsSet == otherInvalidlyInvitedUserIdsSet
    }

    /// When comparing member states, ignore the `didJoinFromInviteLink` field.
    /// This field is not stored as part of memberships in group snapshots from
    /// the service, and is only computed when a member joins a group and we add
    /// them locally. If our local membership differs from a group snapshot's
    /// only in the `didJoinFromInviteLink` field, we want to consider them
    /// equal to avoid clobbering our local state.
    private static func memberStates(
        _ memberStates: MemberStateMap,
        areEqualTo otherMemberStates: MemberStateMap
    ) -> Bool {

        func hardcodeDidJoinViaInviteLink(for groupMemberState: GroupMemberState) -> GroupMemberState {
            switch groupMemberState {
            case .fullMember(let role, _):
                return .fullMember(role: role, didJoinFromInviteLink: false)
            default:
                return groupMemberState
            }
        }

        guard memberStates.count == otherMemberStates.count else {
            return false
        }

        return memberStates.allSatisfy { (key, value) -> Bool in
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
                memberState = .fullMember(role: legacyMemberState.role, didJoinFromInviteLink: false)
            }
            result[address] = memberState
        }
        return result
    }

    // MARK: -

    @objc
    public static var empty: GroupMembership {
        return Builder().build()
    }

    @objc
    public static func normalize(_ addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        return Array(Set(addresses))
            .sorted(by: { (l, r) in l.compare(r) == .orderedAscending })
    }

    public var asBuilder: Builder {
        return Builder(
            memberStates: memberStates,
            bannedMembers: bannedMembers,
            invalidInviteMap: invalidInviteMap
        )
    }

    public override var debugDescription: String {
        var result = "[\n"
        for address in GroupMembership.normalize(Array(allMembersOfAnyKind)) {
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
}

// MARK: - Accessors

public extension GroupMembership {

    var fullMemberAdministrators: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter { $0.value.isAdministrator && $0.value.isFullMember }.map { $0.key })
    }

    var fullMembers: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter { $0.value.isFullMember }.map { $0.key })
    }

    var invitedMembers: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter { $0.value.isInvited }.map { $0.key })
    }

    var requestingMembers: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter { $0.value.isRequesting }.map { $0.key })
    }

    var fullOrInvitedMembers: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter {
            $0.value.isFullMember || $0.value.isInvited
        }.map { $0.key })
    }

    var invitedOrRequestMembers: Set<SignalServiceAddress> {
        return Set(memberStates.lazy.filter {
            $0.value.isInvited || $0.value.isRequesting
        }.map { $0.key })
    }

    var allMembersOfAnyKind: Set<SignalServiceAddress> {
        return Set(memberStates.keys)
    }

    var allMembersOfAnyKindServiceIds: Set<ServiceId> {
        return Set(memberStates.keys.lazy.compactMap { $0.serviceId })
    }
}

public extension GroupMembership {

    func role(for serviceId: ServiceId) -> TSGroupMemberRole? {
        return role(for: SignalServiceAddress(serviceId))
    }

    func role(for address: SignalServiceAddress) -> TSGroupMemberRole? {
        guard let memberState = memberStates[address] else {
            return nil
        }
        return memberState.role
    }

    func isFullOrInvitedAdministrator(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        switch memberState {
        case .fullMember(let role, _):
            return role == .administrator
        case .invited(let role, _):
            return role == .administrator
        case .requesting:
            return false
        }
    }

    func isFullOrInvitedAdministrator(_ serviceId: ServiceId) -> Bool {
        return isFullOrInvitedAdministrator(SignalServiceAddress(serviceId))
    }

    @objc
    func isFullMemberAndAdministrator(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isAdministrator && memberState.isFullMember
    }

    func isFullMemberAndAdministrator(_ serviceId: ServiceId) -> Bool {
        return isFullMemberAndAdministrator(SignalServiceAddress(serviceId))
    }

    @objc
    func isFullMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isFullMember
    }

    func isFullMember(_ serviceId: ServiceId) -> Bool {
        return isFullMember(SignalServiceAddress(serviceId))
    }

    @objc
    func isInvitedMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isInvited
    }

    func isInvitedMember(_ serviceId: ServiceId) -> Bool {
        return isInvitedMember(SignalServiceAddress(serviceId))
    }

    func isRequestingMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isRequesting
    }

    func isRequestingMember(_ serviceId: ServiceId) -> Bool {
        return isRequestingMember(SignalServiceAddress(serviceId))
    }

    func isMemberOfAnyKind(_ address: SignalServiceAddress) -> Bool {
        return memberStates[address] != nil
    }

    func isMemberOfAnyKind(_ serviceId: ServiceId) -> Bool {
        return isMemberOfAnyKind(SignalServiceAddress(serviceId))
    }

    func isBannedMember(_ aci: Aci) -> Bool {
        return bannedMembers[aci] != nil
    }

    func hasInvalidInvite(forUserId userId: Data) -> Bool {
        return invalidInviteMap[userId] != nil
    }

    /// This method should only be called on invited members.
    func addedByAci(forInvitedMember address: SignalServiceAddress) -> Aci? {
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

    func addedByAci(forInvitedMember serviceId: ServiceId) -> Aci? {
        return addedByAci(forInvitedMember: SignalServiceAddress(serviceId))
    }

    /// This method should only be called for full members.
    func didJoinFromInviteLink(forFullMember address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            owsFailDebug("Missing member: \(address)")
            return false
        }
        switch memberState {
        case .fullMember(_, let didJoinFromInviteLink):
            return didJoinFromInviteLink
        default:
            owsFailDebug("Not a full member.")
            return false
        }
    }

    /// Is this user's profile key exposed to the group?
    func hasProfileKeyInGroup(serviceId: ServiceId) -> Bool {
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
    func canViewProfileKeys(serviceId: ServiceId) -> Bool {
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
}

// MARK: - Builder

public extension GroupMembership {
    struct Builder {
        fileprivate var memberStates = MemberStateMap()
        private var bannedMembers = BannedMembersMap()
        private var invalidInviteMap = InvalidInviteMap()

        public init() {}

        fileprivate init(
            memberStates: MemberStateMap,
            bannedMembers: BannedMembersMap,
            invalidInviteMap: InvalidInviteMap
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

        public mutating func addFullMember(_ aci: Aci, role: TSGroupMemberRole, didJoinFromInviteLink: Bool = false) {
            addFullMember(SignalServiceAddress(aci), role: role, didJoinFromInviteLink: didJoinFromInviteLink)
        }

        public mutating func addFullMember(_ address: SignalServiceAddress,
                                           role: TSGroupMemberRole,
                                           didJoinFromInviteLink: Bool = false) {
            addFullMembers([address], role: role, didJoinFromInviteLink: didJoinFromInviteLink)
        }

        public mutating func addFullMembers(_ addresses: Set<SignalServiceAddress>,
                                            role: TSGroupMemberRole,
                                            didJoinFromInviteLink: Bool = false) {
            // Dupe is not necessarily an error; you might know of the UUID
            // mapping for a user that another group member doesn't know about.
            addMembers(addresses,
                       withState: .fullMember(role: role, didJoinFromInviteLink: didJoinFromInviteLink),
                       failOnDupe: false)
        }

        public mutating func addInvitedMember(_ serviceId: ServiceId, role: TSGroupMemberRole, addedByAci: Aci) {
            addInvitedMember(SignalServiceAddress(serviceId), role: role, addedByAci: addedByAci)
        }

        public mutating func addInvitedMember(
            _ address: SignalServiceAddress,
            role: TSGroupMemberRole,
            addedByAci: Aci
        ) {
            addInvitedMembers([address], role: role, addedByAci: addedByAci)
        }

        public mutating func addInvitedMembers(
            _ addresses: Set<SignalServiceAddress>,
            role: TSGroupMemberRole,
            addedByAci: Aci
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
            failOnDupe: Bool = true
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

            var memberStates = self.memberStates

            let localProfileInvariantAddress = SignalServiceAddress(phoneNumber: kLocalProfileInvariantPhoneNumber)
            if memberStates[localProfileInvariantAddress] != nil {
                owsFailDebug("Removing localProfileInvariantAddress.")
                memberStates.removeValue(forKey: localProfileInvariantAddress)
            }

            return GroupMembership(memberStates: memberStates,
                                   bannedMembers: bannedMembers,
                                   invalidInviteMap: invalidInviteMap)
        }
    }
}

// MARK: - Local user accessors

public extension GroupMembership {
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

    @objc
    var isLocalUserMemberOfAnyKind: Bool {
        guard let localIdentifiers = tsAccountManager.localIdentifiers else {
            return false
        }

        if isMemberOfAnyKind(localIdentifiers.aciAddress) {
            return true
        }

        return localPniAsInvitedMember(localIdentifiers: localIdentifiers) != nil
    }

    @objc
    var isLocalUserFullMember: Bool {
        guard let localAci = tsAccountManager.localIdentifiers?.aci else {
            return false
        }

        return isFullMember(localAci)
    }

    /// The ID at which the local user is invited, if at all.
    ///
    /// Checks membership for the local ACI first. If none is available, falls
    /// back to checking membership for the local PNI.
    func localUserInvitedAtServiceId(localIdentifiers: LocalIdentifiers) -> ServiceId? {
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
    var isLocalUserInvitedMember: Bool {
        guard let localIdentifiers = tsAccountManager.localIdentifiers else {
            return false
        }

        return localUserInvitedAtServiceId(localIdentifiers: localIdentifiers) != nil
    }

    var isLocalUserRequestingMember: Bool {
        guard let localAci = tsAccountManager.localIdentifiers?.aci else {
            return false
        }

        return isRequestingMember(localAci)
    }

    @objc
    var isLocalUserFullOrInvitedMember: Bool {
        return isLocalUserFullMember || isLocalUserInvitedMember
    }

    var isLocalUserFullMemberAndAdministrator: Bool {
        guard let localAci = tsAccountManager.localIdentifiers?.aci else {
            return false
        }

        return isFullMemberAndAdministrator(localAci)
    }
}

// MARK: - InvalidInviteModel

@objc(GroupMembershipInvalidInviteModel)
private class InvalidInviteModel: MTLModel {
    @objc
    var userId: Data?

    @objc
    var addedByUserId: Data?

    init(userId: Data?, addedByUserId: Data? = nil) {
        self.userId = userId
        self.addedByUserId = addedByUserId
        super.init()
    }

    @objc
    public override init() {
        super.init()
    }

    @objc
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }
}

// MARK: - LegacyMemberState

@objc(_TtCC16SignalServiceKit15GroupMembership11MemberState)
private class LegacyMemberState: MTLModel {
    @objc
    var role: TSGroupMemberRole = .normal

    @objc
    var isPending: Bool = false

    // Only applies for pending members.
    @objc
    var addedByUuid: UUID?

    @objc
    public override init() {
        super.init()
    }

    init(role: TSGroupMemberRole,
         isPending: Bool,
         addedByUuid: UUID? = nil) {
        self.role = role
        self.isPending = isPending
        self.addedByUuid = addedByUuid

        super.init()
    }

    @objc
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public var isAdministrator: Bool {
        return role == .administrator
    }
}
