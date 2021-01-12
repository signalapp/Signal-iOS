//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// Like TSGroupModel, TSGroupModelV2 is intended to be immutable.
//
// NOTE: This class is tightly coupled to TSGroupModelBuilder.
//       If you modify this class - especially if you
//       add any new properties - make sure to update
//       TSGroupModelBuilder.
@objc
public class TSGroupModelV2: TSGroupModel {

    // These properties TSGroupModel, TSGroupModelV2 is intended to be immutable.
    @objc
    var membership: GroupMembership = GroupMembership.empty
    @objc
    public var access: GroupAccess = .defaultForV2
    @objc
    public var secretParamsData: Data = Data()
    @objc
    public var revision: UInt32 = 0
    @objc
    public var avatarUrlPath: String?
    @objc
    public var inviteLinkPassword: Data?
    // We sometimes create "placeholder" models to reflect
    // groups that we don't have access to on the service.
    @objc
    public var isPlaceholderModel: Bool = false
    @objc
    public var wasJustMigrated: Bool = false
    @objc
    public var wasJustCreatedByLocalUser: Bool = false
    @objc
    public var droppedMembers = [SignalServiceAddress]()

    @objc
    public required init(groupId: Data,
                         name: String?,
                         avatarData: Data?,
                         groupMembership: GroupMembership,
                         groupAccess: GroupAccess,
                         revision: UInt32,
                         secretParamsData: Data,
                         avatarUrlPath: String?,
                         inviteLinkPassword: Data?,
                         isPlaceholderModel: Bool,
                         wasJustMigrated: Bool,
                         wasJustCreatedByLocalUser: Bool,
                         addedByAddress: SignalServiceAddress?,
                         droppedMembers: [SignalServiceAddress]) {
        assert(secretParamsData.count > 0)

        self.membership = groupMembership
        self.secretParamsData = secretParamsData
        self.access = groupAccess
        self.revision = revision
        self.avatarUrlPath = avatarUrlPath
        self.inviteLinkPassword = inviteLinkPassword
        self.isPlaceholderModel = isPlaceholderModel
        self.wasJustMigrated = wasJustMigrated
        self.wasJustCreatedByLocalUser = wasJustCreatedByLocalUser
        self.droppedMembers = droppedMembers

        super.init(groupId: groupId,
                   name: name,
                   avatarData: avatarData,
                   members: Array(groupMembership.fullMembers),
                   addedBy: addedByAddress)
    }

    // MARK: - MTLModel

    @objc
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // MARK: -

    @objc
    public override var groupsVersion: GroupsVersion {
        return .V2
    }

    @objc
    public override var groupMembership: GroupMembership {
        return membership
    }

    @objc
    public override var groupMembers: [SignalServiceAddress] {
        return Array(groupMembership.fullMembers)
    }

    public override func isEqual(to model: TSGroupModel,
                                 comparisonMode: TSGroupModelComparisonMode) -> Bool {
        guard super.isEqual(to: model, comparisonMode: comparisonMode) else {
            return false
        }
        guard let other = model as? TSGroupModelV2 else {
            switch comparisonMode {
            case .compareAll:
                return false
            case .userFacingOnly:
                return true
            }
        }
        guard other.membership == membership else {
            return false
        }
        guard other.access == access else {
            return false
        }
        guard other.secretParamsData == secretParamsData else {
            return false
        }
        guard comparisonMode != .compareAll || other.revision == revision else {
            return false
        }
        guard other.avatarUrlPath == avatarUrlPath else {
            return false
        }
        guard other.inviteLinkPassword == inviteLinkPassword else {
            return false
        }
        guard other.droppedMembers.stableSort() == droppedMembers.stableSort() else {
            return false
        }
        // Ignore isPlaceholderModel & wasJustMigrated & wasJustCreatedByLocalUser.
        return true
    }

    @objc
    public override var debugDescription: String {
        var result = "["
        result += "groupId: \(groupId.hexadecimalString),\n"
        result += "groupsVersion: \(groupsVersion),\n"
        result += "groupName: \(String(describing: groupName)),\n"
        result += "groupAvatarData: \(String(describing: groupAvatarData?.hexadecimalString.prefix(32))),\n"
        result += "membership: \(groupMembership.debugDescription),\n"
        result += "access: \(access.debugDescription),\n"
        result += "secretParamsData: \(secretParamsData.hexadecimalString.prefix(32)),\n"
        result += "revision: \(revision),\n"
        result += "avatarUrlPath: \(String(describing: avatarUrlPath)),\n"
        result += "inviteLinkPassword: \(inviteLinkPassword?.hexadecimalString ?? "None"),\n"
        result += "addedByAddress: \(addedByAddress?.debugDescription ?? "None"),\n"
        result += "isPlaceholderModel: \(isPlaceholderModel),\n"
        result += "wasJustMigrated: \(wasJustMigrated),\n"
        result += "wasJustCreatedByLocalUser: \(wasJustCreatedByLocalUser),\n"
        result += "droppedMembers: \(droppedMembers),\n"
        result += "]"
        return result
    }
}

// MARK: -

@objc
public extension TSGroupModelV2 {
    var groupInviteLinkMode: GroupsV2LinkMode {
        guard let inviteLinkPassword = inviteLinkPassword,
            !inviteLinkPassword.isEmpty else {
                return .disabled
        }

        switch access.addFromInviteLink {
        case .any:
            return .enabledWithoutApproval
        case .administrator:
            return .enabledWithApproval
        default:
            return .disabled
        }
    }

    var isGroupInviteLinkEnabled: Bool {
        if let inviteLinkPassword = inviteLinkPassword,
            !inviteLinkPassword.isEmpty,
            access.canJoinFromInviteLink {
            return true
        }
        return false
    }
}

// MARK: -

@objc
public extension TSGroupModel {
    var isPlaceholder: Bool {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return false
        }
        return groupModelV2.isPlaceholderModel
    }

    var wasJustMigratedToV2: Bool {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return false
        }
        return groupModelV2.wasJustMigrated
    }

    var wasJustCreatedByLocalUserV2: Bool {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return false
        }
        return groupModelV2.wasJustCreatedByLocalUser
    }

    var getDroppedMembers: [SignalServiceAddress] {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return []
        }
        return groupModelV2.droppedMembers
    }
}
