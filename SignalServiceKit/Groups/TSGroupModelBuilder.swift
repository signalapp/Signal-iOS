//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct TSGroupModelBuilder {

    private enum GroupVersion {
        case V1(groupId: Data)
        case V2(secretParamsData: Data)
    }

    private let groupVersion: GroupVersion

    public var name: String?
    public var descriptionText: String?
    public var avatarDataState: TSGroupModel.AvatarDataState = .missing
    public var groupMembership = GroupMembership()
    public var groupAccess: GroupAccess?
    public var groupV2Revision: UInt32 = 0
    public var avatarUrlPath: String?
    public var inviteLinkPassword: Data?
    public var isAnnouncementsOnly: Bool = false

    public var isJoinRequestPlaceholder: Bool = false
    public var addedByAddress: SignalServiceAddress?
    public var wasJustMigrated: Bool = false
    public var didJustAddSelfViaGroupLink: Bool = false

    private init(groupVersion: GroupVersion) {
        self.groupVersion = groupVersion
    }

    public init(secretParams: GroupSecretParams) {
        self.init(groupVersion: .V2(secretParamsData: secretParams.serialize()))
    }

    fileprivate init(groupModel: TSGroupModel) {
        if let v2 = groupModel as? TSGroupModelV2 {
            self.init(groupVersion: .V2(secretParamsData: v2.secretParamsData))

            self.groupAccess = v2.access
            self.groupV2Revision = v2.revision
            self.avatarUrlPath = v2.avatarUrlPath
            self.inviteLinkPassword = v2.inviteLinkPassword
            self.isAnnouncementsOnly = v2.isAnnouncementsOnly
            self.descriptionText = v2.descriptionText

            // Do not copy transient properties:
            //
            // * isJoinRequestPlaceholder
            // * wasJustMigrated
            // * didJustAddSelfViaGroupLink
            //
            // We want to discard these values when updating group models.
        } else {
            self.init(groupVersion: .V1(groupId: groupModel.groupId))
        }

        self.name = groupModel.groupName
        self.avatarDataState = groupModel.avatarDataState
        self.groupMembership = groupModel.groupMembership
        self.addedByAddress = groupModel.addedByAddress
    }

    // Convert a group state proto received from the service
    // into a group model.
    private init(groupV2Snapshot: GroupV2Snapshot) throws {
        self.init(secretParams: groupV2Snapshot.groupSecretParams)
        self.name = groupV2Snapshot.title
        self.descriptionText = groupV2Snapshot.descriptionText
        self.avatarDataState = groupV2Snapshot.avatarDataState
        self.groupMembership = groupV2Snapshot.groupMembership
        self.groupAccess = groupV2Snapshot.groupAccess
        self.groupV2Revision = groupV2Snapshot.revision
        self.avatarUrlPath = groupV2Snapshot.avatarUrlPath
        self.inviteLinkPassword = groupV2Snapshot.inviteLinkPassword
        self.isAnnouncementsOnly = groupV2Snapshot.isAnnouncementsOnly
        self.isJoinRequestPlaceholder = false
        self.wasJustMigrated = false
        self.didJustAddSelfViaGroupLink = false
    }

    static func builderForSnapshot(groupV2Snapshot: GroupV2Snapshot, transaction: DBWriteTransaction) throws -> TSGroupModelBuilder {
        return try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot)
    }

    public mutating func apply(options: TSGroupModelOptions) {
        if options.contains(.didJustAddSelfViaGroupLink) {
            didJustAddSelfViaGroupLink = true
        }
    }

    public func build() throws -> TSGroupModel {
        let allUsers = groupMembership.allMembersOfAnyKind
        for recipientAddress in allUsers {
            guard recipientAddress.isValid else {
                throw OWSAssertionError("Invalid address.")
            }
        }

        var name: String?
        if let strippedName = self.name?.stripped.nilIfEmpty {
            name = strippedName
        }

        switch groupVersion {
        case .V1(let groupId):
            guard GroupManager.isValidGroupId(groupId, groupsVersion: .V1) else {
                throw OWSAssertionError("Invalid groupId.")
            }
            return TSGroupModel(
                groupId: groupId,
                name: name,
                avatarData: avatarDataState.dataIfPresent,
                members: Array(groupMembership.fullMembers),
                addedBy: addedByAddress,
            )
        case .V2(let secretParamsData):
            let groupSecretParams = try GroupSecretParams(contents: secretParamsData)

            return TSGroupModelV2(
                groupId: try groupSecretParams.getPublicParams().getGroupIdentifier().serialize(),
                name: name,
                descriptionText: descriptionText?.stripped.nilIfEmpty,
                avatarDataState: avatarDataState,
                groupMembership: groupMembership,
                groupAccess: groupAccess ?? .defaultForV2,
                revision: groupV2Revision,
                secretParamsData: groupSecretParams.serialize(),
                avatarUrlPath: avatarUrlPath,
                inviteLinkPassword: inviteLinkPassword,
                isAnnouncementsOnly: isAnnouncementsOnly,
                isJoinRequestPlaceholder: isJoinRequestPlaceholder,
                wasJustMigrated: wasJustMigrated,
                didJustAddSelfViaGroupLink: didJustAddSelfViaGroupLink,
                addedByAddress: addedByAddress,
            )
        }
    }

    public func buildAsV2() throws -> TSGroupModelV2 {
        guard let model = try build() as? TSGroupModelV2 else {
            throw OWSAssertionError("[GV1] Should be impossible to create a V1 group!")
        }
        return model
    }
}

// MARK: -

public extension TSGroupModel {
    var asBuilder: TSGroupModelBuilder {
        return TSGroupModelBuilder(groupModel: self)
    }
}

// MARK: -

public struct TSGroupModelOptions: OptionSet {
    public let rawValue: Int

    public static let didJustAddSelfViaGroupLink = TSGroupModelOptions(rawValue: 1 << 0)
    public static let throttle = TSGroupModelOptions(rawValue: 1 << 1)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
