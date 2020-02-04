//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// This class is immutable.
@objc
public class GroupMembership: MTLModel {
    // This class is immutable.
    @objc
    internal class State: MTLModel {
        // GroupsV2 TODO: Use TSGroupMemberRole instead.
        var isAdministrator: Bool = false
        var isPending: Bool = false

        // Only applies for pending members.
        var addedByUuid: UUID?

        @objc
        public override init() {
            super.init()
        }

        init(isAdministrator: Bool,
             isPending: Bool,
             addedByUuid: UUID? = nil) {
            self.isAdministrator = isAdministrator
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
    }

    // By using a single dictionary we ensure that no address has more than one state.
    internal typealias StateMap = [SignalServiceAddress: State]
    private var stateMap: StateMap

    @objc
    public var nonAdminMembers: Set<SignalServiceAddress> {
        return Set(stateMap.filter { !$0.value.isAdministrator && !$0.value.isPending }.keys)
    }
    @objc
    public var administrators: Set<SignalServiceAddress> {
        return Set(stateMap.filter { $0.value.isAdministrator && !$0.value.isPending }.keys)
    }
    // allMembers includes all non-pending members,
    // i.e. normal and administrator members.
    @objc
    public var nonPendingMembers: Set<SignalServiceAddress> {
        return Set(stateMap.filter { !$0.value.isPending }.keys)
    }

    @objc
    public var pendingNonAdminMembers: Set<SignalServiceAddress> {
        return Set(stateMap.filter { !$0.value.isAdministrator && $0.value.isPending }.keys)
    }
    @objc
    public var pendingAdministrators: Set<SignalServiceAddress> {
        return Set(stateMap.filter { $0.value.isAdministrator && $0.value.isPending }.keys)
    }
    // pendingMembers includes normal and administrator "pending members".
    @objc
    public var pendingMembers: Set<SignalServiceAddress> {
        return Set(stateMap.filter { $0.value.isPending }.keys)
    }

    // allUsers includes _all_ users:
    //
    // * Normal and administrator.
    // * Pending and non-pending.
    @objc
    public var allUsers: Set<SignalServiceAddress> {
        return Set(stateMap.keys)
    }

    public struct Builder {
        private var stateMap = StateMap()

        public init() {}

        internal init(stateMap: StateMap) {
            self.stateMap = stateMap
        }

        public mutating func remove(_ address: SignalServiceAddress) {
            stateMap.removeValue(forKey: address)
        }

        public mutating func remove(_ addresses: Set<SignalServiceAddress>) {
            for address in addresses {
                remove(address)
            }
        }

        public mutating func addNonPendingMember(_ address: SignalServiceAddress,
                                                 isAdministrator: Bool) {
            addNonPendingMembers([address], isAdministrator: isAdministrator)
        }

        public mutating func addNonPendingMembers(_ addresses: Set<SignalServiceAddress>,
                                                  isAdministrator: Bool) {
            for address in addresses {
                if stateMap[address] != nil {
                    owsFailDebug("Duplicate address.")
                }
                stateMap[address] = State(isAdministrator: isAdministrator, isPending: false, addedByUuid: nil)
            }
        }

        public mutating func addPendingMember(_ address: SignalServiceAddress,
                                              isAdministrator: Bool,
                                              addedByUuid: UUID) {
            addPendingMembers([address], isAdministrator: isAdministrator, addedByUuid: addedByUuid)
        }

        public mutating func addPendingMembers(_ addresses: Set<SignalServiceAddress>,
                                               isAdministrator: Bool,
                                               addedByUuid: UUID) {
            for address in addresses {
                if stateMap[address] != nil {
                    owsFailDebug("Duplicate address.")
                }
                stateMap[address] = State(isAdministrator: isAdministrator, isPending: true, addedByUuid: addedByUuid)
            }
        }

        public mutating func copyMember(_ address: SignalServiceAddress,
                                        from oldGroupMembership: GroupMembership) {
            guard let state = oldGroupMembership.stateMap[address] else {
                owsFailDebug("Unknown address")
                return
            }
            if stateMap[address] != nil {
                owsFailDebug("Duplicate address.")
            }
            stateMap[address] = state
        }

        internal func asStateMap() -> StateMap {
            return stateMap
        }

        public func build() -> GroupMembership {
            return GroupMembership(stateMap: stateMap)
        }
    }

    @objc
    public override init() {
        self.stateMap = StateMap()

        super.init()
    }

    @objc
    required public init?(coder aDecoder: NSCoder) {
        self.stateMap = StateMap()
        super.init(coder: aDecoder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        self.stateMap = StateMap()
        try super.init(dictionary: dictionaryValue)
    }

    internal init(stateMap: StateMap) {
        self.stateMap = stateMap

        super.init()
    }

    @objc
    public init(v1Members: Set<SignalServiceAddress>) {
        var builder = Builder()
        builder.addNonPendingMembers(v1Members, isAdministrator: false)
        self.stateMap = builder.asStateMap()

        super.init()
    }

    @objc
    public static var empty: GroupMembership {
        return Builder().build()
    }

    public func isPending(_ address: SignalServiceAddress) -> Bool {
        guard let state = stateMap[address] else {
            owsFailDebug("Unknown address")
            return false
        }
        return state.isPending
    }

    public func isAdministrator(_ address: SignalServiceAddress) -> Bool {
        guard let state = stateMap[address] else {
            owsFailDebug("Unknown address")
            return false
        }
        return state.isAdministrator
    }

    // When we check "is X a member?" we might mean...
    //
    // * Is X a "full" member or a pending member?
    // * Is X a "full" member and not a pending member?
    // * Is X a "normal" member and not an administrator member?
    // * Is X a "normal" member or an administrator member?
    // * Some combination thereof.
    //
    // This method is intended tests the inclusive case: pending
    // or non-pending, any role.
    public func isMemberOrPendingMemberOfAnyRole(_ address: SignalServiceAddress) -> Bool {
        return contains(address)
    }

    public func isNonPendingMember(_ address: SignalServiceAddress) -> Bool {
        return nonPendingMembers.contains(address)
    }

    // GroupsV2 TODO: We may remove this method.
    public func contains(_ address: SignalServiceAddress) -> Bool {
        return stateMap[address] != nil
    }

    // GroupsV2 TODO: We may remove this method.
    public func contains(_ uuid: UUID) -> Bool {
        return stateMap[SignalServiceAddress(uuid: uuid)] != nil
    }

    public static func normalize(_ addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        return Array(Set(addresses))
            .sorted(by: { (l, r) in l.compare(r) == .orderedAscending })

    }

    public var asBuilder: Builder {
        return Builder(stateMap: stateMap)
    }

    public override var debugDescription: String {
        var result = "["
        for address in GroupMembership.normalize(Array(allUsers)) {
            guard let state = stateMap[address] else {
                owsFailDebug("Missing state.")
                continue
            }
            result += "\(address), isPending: \(state.isPending), isAdministrator: \(state.isAdministrator)\n"
        }
        result += "]"
        return result
    }
}
