//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct GroupMembership {
    internal struct State {
        let isAdministrator: Bool
        let isPending: Bool
    }
    // By using a single dictionary we ensure that no address has more than one state.
    internal typealias StateMap = [SignalServiceAddress: State]
    private let stateMap: StateMap

    public var nonAdminMembers: Set<SignalServiceAddress> {
        return Set(stateMap.filter { !$0.value.isAdministrator && !$0.value.isPending }.keys)
    }
    public var administrators: Set<SignalServiceAddress> {
        return Set(stateMap.filter { $0.value.isAdministrator && !$0.value.isPending }.keys)
    }
    // allMembers includes normal and administrator members.
    public var allMembers: Set<SignalServiceAddress> {
        return Set(stateMap.filter { !$0.value.isPending }.keys)
    }

    public var pendingNonAdminMembers: Set<SignalServiceAddress> {
        return Set(stateMap.filter { !$0.value.isAdministrator && $0.value.isPending }.keys)
    }
    public var pendingAdministrators: Set<SignalServiceAddress> {
        return Set(stateMap.filter { $0.value.isAdministrator && $0.value.isPending }.keys)
    }
    // allPendingMembers includes normal and administrator "pending members".
    public var allPendingMembers: Set<SignalServiceAddress> {
        return Set(stateMap.filter { $0.value.isPending }.keys)
    }

    // allUsers includes all users:
    //
    // * Normal and administrator.
    // * Pending and non-pending.
    public var allUsers: Set<SignalServiceAddress> {
        return allMembers.union(allPendingMembers)
    }

    public struct Builder {
        private var stateMap = StateMap()

        internal init() {}

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

        public mutating func add(_ address: SignalServiceAddress,
                                 isAdministrator: Bool,
                                 isPending: Bool) {
            add([address], isAdministrator: isAdministrator, isPending: isPending)
        }

        public mutating func add(_ addresses: Set<SignalServiceAddress>,
                                 isAdministrator: Bool,
                                 isPending: Bool) {
            for address in addresses {
                guard stateMap[address] == nil else {
                    owsFailDebug("Duplicate address.")
                    continue
                }
                stateMap[address] = State(isAdministrator: isAdministrator, isPending: isPending)
            }
        }

        public mutating func replace(_ address: SignalServiceAddress,
                                 isAdministrator: Bool,
                                 isPending: Bool) {
            remove(address)
            add([address], isAdministrator: isAdministrator, isPending: isPending)
        }

        internal func asStateMap() -> StateMap {
            return stateMap
        }

        public func build() -> GroupMembership {
            return GroupMembership(stateMap: stateMap)
        }
    }

    public init(nonAdminMembers: Set<SignalServiceAddress>,
                administrators: Set<SignalServiceAddress>,
                pendingNonAdminMembers: Set<SignalServiceAddress>,
                pendingAdministrators: Set<SignalServiceAddress>) {

        var builder = Builder()
        builder.add(nonAdminMembers, isAdministrator: false, isPending: false)
        builder.add(administrators, isAdministrator: true, isPending: false)
        builder.add(pendingNonAdminMembers, isAdministrator: false, isPending: true)
        builder.add(pendingAdministrators, isAdministrator: true, isPending: true)
        self.stateMap = builder.asStateMap()
    }

    internal init(stateMap: StateMap) {
        self.stateMap = stateMap
    }

    public init(v1Members: Set<SignalServiceAddress>) {
        var builder = Builder()
        builder.add(v1Members, isAdministrator: false, isPending: false)
        self.stateMap = builder.asStateMap()
    }

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

    public func contains(_ address: SignalServiceAddress) -> Bool {
        return stateMap[address] != nil
    }

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

    // Can be used to force a single user to be a member,
    // namely the local user.
    public func withNonAdminMember(address: SignalServiceAddress) -> GroupMembership {
        var builder = self.asBuilder
        builder.replace(address, isAdministrator: false, isPending: false)
        return builder.build()
    }

    public var debugDescription: String {
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
