//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum GroupV2Access: UInt, Codable {
    case unknown = 0
    case any
    case member
    case administrator
}

// MARK: -

@objc
public class GroupAccess: MTLModel {
    @objc
    public var member: GroupV2Access = .unknown
    @objc
    public var attributes: GroupV2Access = .unknown

    public init(member: GroupV2Access,
                attributes: GroupV2Access) {
        self.member = member
        self.attributes = attributes

        super.init()
    }

    @objc
    public override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public static var allAccess: GroupAccess {
        return GroupAccess(member: .any, attributes: .any)
    }

    @objc
    public static var forV1: GroupAccess {
        return allAccess
    }

    public class func groupV2Access(forProtoAccess value: GroupsProtoAccessControlAccessRequired) -> GroupV2Access {
        switch value {
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        default:
            return .unknown
        }
    }

    public class func protoAccess(forGroupV2Access value: GroupV2Access) -> GroupsProtoAccessControlAccessRequired {
        switch value {
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        default:
            return .unknown
        }
    }
}
