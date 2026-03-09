//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum GroupV2Access: UInt, Codable, CustomStringConvertible {
    case unknown = 0
    case any
    case member
    case administrator
    case unsatisfiable

    public static func access(forProtoAccess value: GroupsProtoAccessControlAccessRequired) -> GroupV2Access {
        switch value {
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        case .unsatisfiable:
            return .unsatisfiable
        default:
            return .unknown
        }
    }

    public var protoAccess: GroupsProtoAccessControlAccessRequired {
        switch self {
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        case .unsatisfiable:
            return .unsatisfiable
        default:
            return .unknown
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .any:
            return "any"
        case .member:
            return "member"
        case .administrator:
            return "administrator"
        case .unsatisfiable:
            return "unsatisfiable"
        }
    }
}

// MARK: -

// This class is immutable.
@objc
public final class GroupAccess: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public init?(coder: NSCoder) {
        self.addFromInviteLink = (coder.decodeObject(of: NSNumber.self, forKey: "addFromInviteLink")?.uintValue).flatMap(GroupV2Access.init(rawValue:)) ?? .unknown
        self.attributes = (coder.decodeObject(of: NSNumber.self, forKey: "attributes")?.uintValue).flatMap(GroupV2Access.init(rawValue:)) ?? .unknown
        self.members = (coder.decodeObject(of: NSNumber.self, forKey: "members")?.uintValue).flatMap(GroupV2Access.init(rawValue:)) ?? .unknown
        self.memberLabels = (coder.decodeObject(of: NSNumber.self, forKey: "memberLabels")?.uintValue).flatMap(GroupV2Access.init(rawValue:)) ?? GroupAccess.defaultForV2.memberLabels
    }

    public func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: self.addFromInviteLink.rawValue), forKey: "addFromInviteLink")
        coder.encode(NSNumber(value: self.attributes.rawValue), forKey: "attributes")
        coder.encode(NSNumber(value: self.members.rawValue), forKey: "members")
        coder.encode(NSNumber(value: self.memberLabels.rawValue), forKey: "memberLabels")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(addFromInviteLink)
        hasher.combine(attributes)
        hasher.combine(members)
        hasher.combine(memberLabels)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.addFromInviteLink == object.addFromInviteLink else { return false }
        guard self.attributes == object.attributes else { return false }
        guard self.members == object.members else { return false }
        guard self.memberLabels == object.memberLabels else { return false }
        return true
    }

    public let members: GroupV2Access
    public let attributes: GroupV2Access
    public let addFromInviteLink: GroupV2Access
    public let memberLabels: GroupV2Access

    public init(members: GroupV2Access, attributes: GroupV2Access, addFromInviteLink: GroupV2Access, memberLabels: GroupV2Access) {
        // Ensure we always have valid values.
        self.members = Self.filter(forMembers: members)
        self.attributes = Self.filter(forAttributes: attributes)
        self.addFromInviteLink = Self.filter(forAddFromInviteLink: addFromInviteLink)
        self.memberLabels = Self.filter(forMemberLabels: memberLabels)

        super.init()
    }

    public static func filter(forMembers value: GroupV2Access) -> GroupV2Access {
        switch value {
        case .member, .administrator:
            return value
        default:
            owsFailDebug("Invalid access level: \(value)")
            return .unknown
        }
    }

    public static func filter(forAttributes value: GroupV2Access) -> GroupV2Access {
        switch value {
        case .member, .administrator:
            return value
        default:
            owsFailDebug("Invalid access level: \(value)")
            return .unknown
        }
    }

    public static func filter(forAddFromInviteLink value: GroupV2Access) -> GroupV2Access {
        switch value {
        case .unknown:
            // .unknown is valid for groups created before group links were added.
            return value
        case .unsatisfiable, .administrator, .any:
            return value
        default:
            owsFailDebug("Invalid access level: \(value)")
            return .unknown
        }
    }

    public static func filter(forMemberLabels value: GroupV2Access) -> GroupV2Access {
        switch value {
        case .unknown:
            // Valid for groups created before member label permission was added. Use default.
            return GroupAccess.defaultForV2.memberLabels
        case .member, .administrator:
            return value
        default:
            owsFailDebug("Invalid access level: \(value)")
            return .unknown
        }
    }

#if TESTABLE_BUILD
    public static var allAccess: GroupAccess {
        return GroupAccess(members: .member, attributes: .member, addFromInviteLink: .any, memberLabels: .member)
    }
#endif

    @objc
    public static var defaultForV2: GroupAccess {
        return GroupAccess(members: .member, attributes: .member, addFromInviteLink: .unsatisfiable, memberLabels: .member)
    }

    override public var debugDescription: String {
        return "[members: \(members), attributes: \(attributes), addFromInviteLink: \(addFromInviteLink), memberLabels: \(memberLabels), ]"
    }
}

// MARK: -

@objc
public extension GroupAccess {
    var canJoinFromInviteLink: Bool {
        // TODO: Should this include .member?
        addFromInviteLink == .any ||
            addFromInviteLink == .administrator
    }
}
