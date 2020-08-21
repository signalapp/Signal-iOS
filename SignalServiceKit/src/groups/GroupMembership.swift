//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension TSGroupMemberRole {
    static func role(for value: GroupsProtoMemberRole) -> TSGroupMemberRole? {
        switch value {
        case .`default`:
            return .normal
        case .administrator:
            return .administrator
        default:
            owsFailDebug("Invalid value: \(value.rawValue)")
            return nil
        }
    }

    var asProtoRole: GroupsProtoMemberRole {
        switch self {
        case .normal:
            return .`default`
        case .administrator:
            return .administrator
        }
    }
}

// MARK: -

// NOTE: We only use this class for backwards compatibility.
@objc(_TtCC16SignalServiceKit15GroupMembership11MemberState)
class LegacyMemberState: MTLModel {
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

// MARK: -

extension TSGroupMemberRole: Codable {}

// MARK: -

private enum GroupMemberState {
    case fullMember(role: TSGroupMemberRole)
    case pendingProfileKey(role: TSGroupMemberRole, addedByUuid: UUID)
    // These members don't yet have any attributes.
    // We'll add PendingRequestMemberState if they ever do.
    case pendingRequest

    var role: TSGroupMemberRole {
        switch self {
        case .fullMember(let role):
            return role
        case .pendingProfileKey(let role, _):
            return role
        case .pendingRequest:
            return .`normal`
        }
    }

    var isAdministrator: Bool {
        role == .administrator
    }

    var isFullMember: Bool {
        switch self {
        case .fullMember:
            return true
        default:
            return false
        }
    }

    var isPendingProfileKey: Bool {
        switch self {
        case .pendingProfileKey:
            return true
        default:
            return false
        }
    }

    var isPendingRequest: Bool {
        switch self {
        case .pendingRequest:
            return true
        default:
            return false
        }
    }
}

// MARK: -

extension GroupMemberState: Codable {

    private enum TypeKey: UInt, Codable {
        case fullMember = 0
        case pendingProfileKey = 1
        case pendingRequest = 2
    }

    private enum CodingKeys: String, CodingKey {
        case typeKey
        case role
        case addedByUuid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let typeKey = try container.decode(TypeKey.self, forKey: .typeKey)
        switch typeKey {
        case .fullMember:
            let role = try container.decode(TSGroupMemberRole.self, forKey: .role)
            self = .fullMember(role: role)
        case .pendingProfileKey:
            let role = try container.decode(TSGroupMemberRole.self, forKey: .role)
            let addedByUuid = try container.decode(UUID.self, forKey: .addedByUuid)
            self = .pendingProfileKey(role: role, addedByUuid: addedByUuid)
        case .pendingRequest:
            self = .pendingRequest
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .fullMember(let role):
            try container.encode(TypeKey.fullMember, forKey: .typeKey)
            try container.encode(role, forKey: .role)
        case .pendingProfileKey(let role, let addedByUuid):
            try container.encode(TypeKey.pendingProfileKey, forKey: .typeKey)
            try container.encode(role, forKey: .role)
            try container.encode(addedByUuid, forKey: .addedByUuid)
        case .pendingRequest:
            try container.encode(TypeKey.pendingRequest, forKey: .typeKey)
        }
    }
}

// MARK: -

extension GroupMemberState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fullMember:
            return ".fullMember"
        case .pendingProfileKey:
            return ".pendingProfileKey"
        case .pendingRequest:
            return ".pendingRequest"
        }
    }
}

// MARK: -

// This class is immutable.
@objc(GroupMembershipInvalidInviteModel)
class InvalidInviteModel: MTLModel {
    @objc
    var userId: Data?

    @objc
    var addedByUserId: Data?

    @objc
    public override init() {
        super.init()
    }

    init(userId: Data?, addedByUserId: Data? = nil) {
        self.userId = userId
        self.addedByUserId = addedByUserId

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

// MARK: -

// This class is immutable.
@objc
public class GroupMembership: MTLModel {

    typealias LegacyMemberStateMap = [SignalServiceAddress: LegacyMemberState]

    // By using a single dictionary we ensure that no address has more than one state.
    fileprivate typealias MemberStateMap = [SignalServiceAddress: GroupMemberState]
    fileprivate var memberStates: MemberStateMap

    typealias InvalidInviteMap = [Data: InvalidInviteModel]
    @objc
    var invalidInviteMap: InvalidInviteMap

    @objc
    public override init() {
        self.memberStates = MemberStateMap()
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
                owsFailDebug("Error: \(error)")
                return nil
            }
        } else if let legacyMemberStateMap = aDecoder.decodeObject(forKey: Self.legacyMemberStatesKey) as? LegacyMemberStateMap {
            self.memberStates = Self.convertLegacyMemberStateMap(legacyMemberStateMap)
        } else {
            owsFailDebug("Could not decode.")
            return nil
        }

        super.init()
    }

    private static let memberStatesKey = "memberStates"
    private static let legacyMemberStatesKey = "memberStateMap"
    private static let invalidInviteMapKey = "invalidInviteMap"

    public override func encode(with aCoder: NSCoder) {
        let encoder = JSONEncoder()
        do {
            let memberStatesData = try encoder.encode(self.memberStates)
            aCoder.encode(memberStatesData, forKey: Self.memberStatesKey)
        } catch {
            owsFailDebug("Error: \(error)")
        }

        aCoder.encode(invalidInviteMap, forKey: Self.invalidInviteMapKey)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        if let invalidInviteMap = dictionaryValue[Self.invalidInviteMapKey] as? InvalidInviteMap {
            self.invalidInviteMap = invalidInviteMap
        } else {
            // invalidInviteMap is optional.
            self.invalidInviteMap = [:]
        }

        if let memberStates = dictionaryValue[Self.memberStatesKey] as? MemberStateMap {
            self.memberStates = memberStates
        } else if let legacyMemberStateMap = dictionaryValue[Self.legacyMemberStatesKey] as? LegacyMemberStateMap {
            self.memberStates = Self.convertLegacyMemberStateMap(legacyMemberStateMap)
        } else {
            throw OWSAssertionError("Could not decode.")
        }

        super.init()
    }

    fileprivate init(memberStates: MemberStateMap, invalidInviteMap: InvalidInviteMap) {
        self.memberStates = memberStates
        self.invalidInviteMap = invalidInviteMap

        super.init()
    }

    @objc
    public init(v1Members: Set<SignalServiceAddress>) {
        var builder = Builder()
        builder.addFullMembers(v1Members, role: .normal)
        self.memberStates = builder.asMemberStateMap()
        self.invalidInviteMap = [:]

        super.init()
    }

    private static func convertLegacyMemberStateMap(_ legacyMemberStateMap: LegacyMemberStateMap) -> MemberStateMap {
        var result = MemberStateMap()
        for (address, legacyMemberState) in legacyMemberStateMap {
            let memberState: GroupMemberState
            if legacyMemberState.isPending {
                if let addedByUuid = legacyMemberState.addedByUuid {
                    memberState = .pendingProfileKey(role: legacyMemberState.role,
                                                     addedByUuid: addedByUuid)
                } else {
                    owsFailDebug("Missing addedByUuid.")
                    continue
                }
            } else {
                memberState = .fullMember(role: legacyMemberState.role)
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

    public func hasInvalidInvite(forUserId userId: Data) -> Bool {
        return invalidInviteMap[userId] != nil
    }

    public var invalidInvites: [InvalidInvite] {
        var result = [InvalidInvite]()
        for invalidInvite in invalidInviteMap.values {
            guard let userId = invalidInvite.userId else {
                owsFailDebug("Missing userId.")
                continue
            }
            guard let addedByUserId = invalidInvite.addedByUserId else {
                owsFailDebug("Missing addedByUserId.")
                continue
            }
            result.append(InvalidInvite(userId: userId, addedByUserId: addedByUserId))
        }
        return result
    }

    public var asBuilder: Builder {
        return Builder(memberStates: memberStates, invalidInviteMap: invalidInviteMap)
    }

    public override var debugDescription: String {
        var result = "["
        for address in GroupMembership.normalize(Array(allMembersOfAnyKind)) {
            guard let memberState = memberStates[address] else {
                owsFailDebug("Missing memberState.")
                continue
            }
            result += "\(address), memberType: \(memberState)\n"
        }
        result += "]"
        return result
    }
}

// MARK: - Swift Accessors

public extension GroupMembership {

    var fullMemberAdministrators: Set<SignalServiceAddress> {
        return Set(memberStates.filter { $0.value.isAdministrator && $0.value.isFullMember }.keys)
    }

    var fullMembers: Set<SignalServiceAddress> {
        return Set(memberStates.filter { $0.value.isFullMember }.keys)
    }

    var pendingProfileKeyMembers: Set<SignalServiceAddress> {
        return Set(memberStates.filter { $0.value.isPendingProfileKey }.keys)
    }

    var pendingRequestMembers: Set<SignalServiceAddress> {
        return Set(memberStates.filter { $0.value.isPendingRequest }.keys)
    }

    var fullOrPendingProfileKeyMembers: Set<SignalServiceAddress> {
        return Set(memberStates.filter {
            $0.value.isFullMember || $0.value.isPendingProfileKey
        }.keys)
    }

    var pendingProfileKeyOrRequestMembers: Set<SignalServiceAddress> {
        return Set(memberStates.filter {
            $0.value.isPendingProfileKey || $0.value.isPendingRequest
        }.keys)
    }

    // allMembersOfAnyKind includes _all_ members:
    //
    // * Normal and administrator.
    // * Normal, pending profile key, requesting.
    var allMembersOfAnyKind: Set<SignalServiceAddress> {
        return Set(memberStates.keys)
    }

    // allUsers includes _all_ members:
    //
    // * Normal and administrator.
    // * Normal, pending profile key, requesting.
    var allMemberUuidsOfAnyKind: Set<UUID> {
        return Set(memberStates.keys.compactMap { $0.uuid })
    }

    func role(for uuid: UUID) -> TSGroupMemberRole? {
        return role(for: SignalServiceAddress(uuid: uuid))
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
        case .fullMember(let role):
            return role == .administrator
        case .pendingProfileKey(let role, _):
            return role == .administrator
        case .pendingRequest:
            return false
        }
    }

    func isFullOrInvitedAdministrator(_ uuid: UUID) -> Bool {
        return isFullOrInvitedAdministrator(SignalServiceAddress(uuid: uuid))
    }

    func isFullMemberAndAdministrator(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isAdministrator && memberState.isFullMember
    }

    func isFullMemberAndAdministrator(_ uuid: UUID) -> Bool {
        return isFullMemberAndAdministrator(SignalServiceAddress(uuid: uuid))
    }

    @objc
    func isFullMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isFullMember
    }

    func isFullMember(_ uuid: UUID) -> Bool {
        isFullMember(SignalServiceAddress(uuid: uuid))
    }

    @objc
    func isPendingProfileKeyMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isPendingProfileKey
    }

    func isPendingProfileKeyMember(_ uuid: UUID) -> Bool {
        isPendingProfileKeyMember(SignalServiceAddress(uuid: uuid))
    }

    func isRequestingMember(_ address: SignalServiceAddress) -> Bool {
        guard let memberState = memberStates[address] else {
            return false
        }
        return memberState.isPendingRequest
    }

    func isRequestingMember(_ uuid: UUID) -> Bool {
        isRequestingMember(SignalServiceAddress(uuid: uuid))
    }

    // Returns true for...
    //
    // * Any type: Full members, "pending invite" members, "requesting" members.
    // * Any role: admin, non-admin.
    //
    // This method is intended tests the inclusive case: pending
    // or non-pending, any role.
    //
    // This method does NOT return true for invalid invites,
    // which don't have a UUID or address associated with them.
    func isMemberOfAnyKind(_ address: SignalServiceAddress) -> Bool {
        return memberStates[address] != nil
    }

    func isMemberOfAnyKind(_ uuid: UUID) -> Bool {
        return isMemberOfAnyKind(SignalServiceAddress(uuid: uuid))
    }

    // This method should only be called for "pending profile key" members.
    func addedByUuid(forPendingProfileKeyMember address: SignalServiceAddress) -> UUID? {
        guard let memberState = memberStates[address] else {
            return nil
        }
        switch memberState {
        case .pendingProfileKey(_, let addedByUuid):
            return addedByUuid
        default:
            owsFailDebug("Not a pending profile key member.")
            return nil
        }
    }
}

// MARK: - Builder

@objc
public extension GroupMembership {
    struct Builder {
        private var memberStates = MemberStateMap()
        private var invalidInviteMap = InvalidInviteMap()

        public init() {}

        fileprivate init(memberStates: MemberStateMap, invalidInviteMap: InvalidInviteMap) {
            self.memberStates = memberStates
            self.invalidInviteMap = invalidInviteMap
        }

        public mutating func remove(_ uuid: UUID) {
            remove(SignalServiceAddress(uuid: uuid))
        }

        public mutating func remove(_ address: SignalServiceAddress) {
            memberStates.removeValue(forKey: address)
        }

        public mutating func remove(_ addresses: Set<SignalServiceAddress>) {
            for address in addresses {
                remove(address)
            }
        }

        public mutating func addFullMember(_ uuid: UUID,
                                           role: TSGroupMemberRole) {
            addFullMember(SignalServiceAddress(uuid: uuid), role: role)
        }

        public mutating func addFullMember(_ address: SignalServiceAddress,
                                           role: TSGroupMemberRole) {
            addFullMembers([address], role: role)
        }

        public mutating func addFullMembers(_ addresses: Set<SignalServiceAddress>,
                                            role: TSGroupMemberRole) {
            for address in addresses {
                if memberStates[address] != nil {
                    owsFailDebug("Duplicate address.")
                }
                memberStates[address] = .fullMember(role: role)
            }
        }

        public mutating func addPendingProfileKeyMember(_ uuid: UUID,
                                                        role: TSGroupMemberRole,
                                                        addedByUuid: UUID) {
            addPendingProfileKeyMember(SignalServiceAddress(uuid: uuid), role: role, addedByUuid: addedByUuid)
        }

        public mutating func addPendingProfileKeyMember(_ address: SignalServiceAddress,
                                                        role: TSGroupMemberRole,
                                                        addedByUuid: UUID) {
            addPendingProfileKeyMembers([address], role: role, addedByUuid: addedByUuid)
        }

        public mutating func addPendingProfileKeyMembers(_ addresses: Set<SignalServiceAddress>,
                                                         role: TSGroupMemberRole,
                                                         addedByUuid: UUID) {
            for address in addresses {
                if memberStates[address] != nil {
                    owsFailDebug("Duplicate address.")
                    continue
                }
                memberStates[address] = .pendingProfileKey(role: role, addedByUuid: addedByUuid)
            }
        }

        public mutating func addRequestingMember(_ uuid: UUID) {
            addRequestingMember(SignalServiceAddress(uuid: uuid))
        }

        public mutating func addRequestingMember(_ address: SignalServiceAddress) {
            addRequestingMembers([address])
        }

        public mutating func addRequestingMembers(_ addresses: Set<SignalServiceAddress>) {
            for address in addresses {
                if memberStates[address] != nil {
                    owsFailDebug("Duplicate address.")
                    continue
                }
                memberStates[address] = .pendingRequest
            }
        }

        public mutating func copyMember(_ address: SignalServiceAddress,
                                        from oldGroupMembership: GroupMembership) {
            guard let memberState = oldGroupMembership.memberStates[address] else {
                owsFailDebug("Unknown address")
                return
            }
            if memberStates[address] != nil {
                owsFailDebug("Duplicate address.")
            }
            memberStates[address] = memberState
        }

        public mutating func addInvalidInvite(userId: Data, addedByUserId: Data) {
            invalidInviteMap[userId] = InvalidInviteModel(userId: userId, addedByUserId: addedByUserId)
        }

        public mutating func removeInvalidInvite(userId: Data) {
            invalidInviteMap.removeValue(forKey: userId)
        }

        public mutating func copyInvalidInvites(from other: GroupMembership) {
            assert(invalidInviteMap.isEmpty)
            invalidInviteMap = other.invalidInviteMap
        }

        fileprivate func asMemberStateMap() -> MemberStateMap {
            return memberStates
        }

        public func build() -> GroupMembership {
            var memberStates = self.memberStates

            let localProfileInvariantAddress = SignalServiceAddress(phoneNumber: kLocalProfileInvariantPhoneNumber)
            if memberStates[localProfileInvariantAddress] != nil {
                owsFailDebug("Removing localProfileInvariantAddress.")
                memberStates.removeValue(forKey: localProfileInvariantAddress)
            }

            return GroupMembership(memberStates: memberStates,
                                   invalidInviteMap: invalidInviteMap)
        }
    }
}
