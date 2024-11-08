//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
public import LibSignalClient

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
    var membership: GroupMembership
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
    @objc
    public var isAnnouncementsOnly: Bool = false
    /// Whether this group model is a placeholder for a group we've requested to
    /// join, but don't yet have access to on the service. Other fields on this
    /// group model may not be populated.
    ///
    /// - Important
    /// The @objc name must remain as-is, so as to correctly deserialize
    /// existing models that were ``NSKeyedArchiver``-ed in the past.
    @objc(isPlaceholderModel)
    public var isJoinRequestPlaceholder: Bool = false
    @objc
    public var wasJustMigrated: Bool = false
    @objc
    public var didJustAddSelfViaGroupLink: Bool = false
    @objc
    public var droppedMembers = [SignalServiceAddress]()
    @objc
    public var descriptionText: String?

    @objc
    public init(groupId: Data,
                name: String?,
                descriptionText: String?,
                avatarData: Data?,
                groupMembership: GroupMembership,
                groupAccess: GroupAccess,
                revision: UInt32,
                secretParamsData: Data,
                avatarUrlPath: String?,
                inviteLinkPassword: Data?,
                isAnnouncementsOnly: Bool,
                isJoinRequestPlaceholder: Bool,
                wasJustMigrated: Bool,
                didJustAddSelfViaGroupLink: Bool,
                addedByAddress: SignalServiceAddress?,
                droppedMembers: [SignalServiceAddress]) {
        self.descriptionText = descriptionText
        self.membership = groupMembership
        self.secretParamsData = secretParamsData
        self.access = groupAccess
        self.revision = revision
        self.avatarUrlPath = avatarUrlPath
        self.inviteLinkPassword = inviteLinkPassword
        self.isAnnouncementsOnly = isAnnouncementsOnly
        self.isJoinRequestPlaceholder = isJoinRequestPlaceholder
        self.wasJustMigrated = wasJustMigrated
        self.didJustAddSelfViaGroupLink = didJustAddSelfViaGroupLink
        self.droppedMembers = droppedMembers

        super.init(groupId: groupId,
                   name: name,
                   avatarData: avatarData,
                   members: [],
                   addedBy: addedByAddress)
    }

    public func secretParams() throws -> GroupSecretParams {
        return try GroupSecretParams(contents: [UInt8](self.secretParamsData))
    }

    public func masterKey() throws -> GroupMasterKey {
        return try secretParams().getMasterKey()
    }

    public func groupInviteLinkUrl() throws -> URL {
        guard let inviteLinkPassword, !inviteLinkPassword.isEmpty else {
            throw OWSAssertionError("Missing password.")
        }
        let masterKey = try self.masterKey()

        var contentsV1Builder = GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1.builder()
        contentsV1Builder.setGroupMasterKey(masterKey.serialize().asData)
        contentsV1Builder.setInviteLinkPassword(inviteLinkPassword)

        var builder = GroupsProtoGroupInviteLink.builder()
        builder.setContents(GroupsProtoGroupInviteLinkOneOfContents.contentsV1(contentsV1Builder.buildInfallibly()))
        let protoData = try builder.buildSerializedData()

        let protoBase64Url = protoData.asBase64Url

        let urlString = "https://signal.group/#\(protoBase64Url)"
        guard let url = URL(string: urlString) else {
            throw OWSAssertionError("Could not construct url.")
        }
        return url
    }

    // MARK: - MTLModel

    @objc
    required public init?(coder aDecoder: NSCoder) {
        self.membership = .empty
        super.init(coder: aDecoder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        self.membership = .empty
        try super.init(dictionary: dictionaryValue)
    }

    public override class func storageBehaviorForProperty(withKey propertyKey: String) -> MTLPropertyStorage {
        if propertyKey == #keyPath(groupMembers) {
            // This is included in groupMembership.
            return MTLPropertyStorageNone
        }
        return super.storageBehaviorForProperty(withKey: propertyKey)
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

    public func hasUserFacingChangeCompared(
        to otherGroupModel: TSGroupModelV2
    ) -> Bool {
        if self === otherGroupModel {
            return false
        }

        guard
            groupName == otherGroupModel.groupName,
            avatarHash == otherGroupModel.avatarHash,
            addedByAddress == otherGroupModel.addedByAddress,
            descriptionText == otherGroupModel.descriptionText,
            membership == otherGroupModel.membership,
            access == otherGroupModel.access,
            isAnnouncementsOnly == otherGroupModel.isAnnouncementsOnly,
            inviteLinkPassword == otherGroupModel.inviteLinkPassword
        else {
            return true
        }

        return false
    }

    @objc
    public override var debugDescription: String {
        var result = "["
        result += "groupId: \(groupId.hexadecimalString),\n"
        result += "groupsVersion: \(groupsVersion),\n"
        result += "groupName: \(String(describing: groupName)),\n"
        result += "avatarHash: \(String(describing: avatarHash)),\n"
        result += "membership: \(groupMembership.debugDescription),\n"
        result += "access: \(access.debugDescription),\n"
        result += "secretParamsData: \(secretParamsData.hexadecimalString.prefix(32)),\n"
        result += "revision: \(revision),\n"
        result += "avatarUrlPath: \(String(describing: avatarUrlPath)),\n"
        result += "inviteLinkPassword: \(inviteLinkPassword?.hexadecimalString ?? "None"),\n"
        result += "isAnnouncementsOnly: \(isAnnouncementsOnly),\n"
        result += "addedByAddress: \(addedByAddress?.debugDescription ?? "None"),\n"
        result += "isJoinRequestPlaceholder: \(isJoinRequestPlaceholder),\n"
        result += "wasJustMigrated: \(wasJustMigrated),\n"
        result += "didJustAddSelfViaGroupLink: \(didJustAddSelfViaGroupLink),\n"
        result += "droppedMembers: \(droppedMembers),\n"
        result += "descriptionText: \(String(describing: descriptionText)),\n"
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
        return groupModelV2.isJoinRequestPlaceholder
    }

    var wasJustMigratedToV2: Bool {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return false
        }
        return groupModelV2.wasJustMigrated
    }

    var didJustAddSelfViaGroupLinkV2: Bool {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return false
        }
        return groupModelV2.didJustAddSelfViaGroupLink
    }

    var getDroppedMembers: [SignalServiceAddress] {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return []
        }
        return groupModelV2.droppedMembers
    }
}

@objc
public extension TSGroupModel {
    private static let appSharedDataDirectory = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
    static let avatarsDirectory = URL(fileURLWithPath: "GroupAvatars", isDirectory: true, relativeTo: appSharedDataDirectory)
    @nonobjc
    private static let avatarsCache = LRUCache<String, Data>(maxSize: 16, nseMaxSize: 0)

    func attemptToMigrateLegacyAvatarDataToDisk() throws {
        guard let legacyAvatarData = legacyAvatarData, !legacyAvatarData.isEmpty else {
            self.legacyAvatarData = nil
            return
        }

        guard Self.isValidGroupAvatarData(legacyAvatarData) else {
            owsFailDebug("Invalid legacy avatar data. Removing it completely")
            self.avatarHash = nil
            self.legacyAvatarData = nil
            return
        }

        try persistAvatarData(legacyAvatarData)
        self.legacyAvatarData = nil
    }

    func persistAvatarData(_ data: Data) throws {
        guard !data.isEmpty else {
            self.avatarHash = nil
            return
        }

        guard Self.isValidGroupAvatarData(data) else {
            throw OWSAssertionError("Invalid group avatar")
        }

        let hash = try Self.hash(forAvatarData: data)

        OWSFileSystem.ensureDirectoryExists(Self.avatarsDirectory.path)

        let filePath = Self.avatarFilePath(forHash: hash)
        guard !OWSFileSystem.fileOrFolderExists(url: filePath) else {
            // Avatar is already persisted.
            self.avatarHash = hash
            return
        }

        try data.write(to: Self.avatarFilePath(forHash: hash))
        Self.avatarsCache.set(key: hash, value: data)

        // Note: Old avatars are explicitly not cleaned up from the file
        // system at this point, as multiple instances of a group model
        // may be floating around referencing different versions of
        // the avatar. We only purge old avatars from the file system
        // when orphan data cleaner deems it safe to do so.

        self.avatarHash = hash
    }

    class func hash(forAvatarData avatarData: Data) throws -> String {
        return Data(SHA256.hash(data: avatarData)).hexadecimalString
    }

    var avatarData: Data? {
        if let avatarHash = avatarHash, let cachedData = Self.avatarsCache.object(forKey: avatarHash) {
            return cachedData
        }

        guard let fileName = avatarFileName else { return nil }
        let filePath = URL(fileURLWithPath: fileName, relativeTo: Self.avatarsDirectory)

        let avatarData: Data
        do {
            avatarData = try Data(contentsOf: filePath)
        } catch {
            owsFailDebug("Failed to read group avatar data \(error)")
            return nil
        }

        guard avatarData.ows_isValidImage else {
            owsFailDebug("Invalid group avatar data.")
            return nil
        }

        return avatarData
    }

    var avatarImage: UIImage? {
        guard let avatarData = avatarData else {
            return nil
        }
        return UIImage(data: avatarData)
    }

    var avatarFileName: String? {
        guard let hash = avatarHash else { return nil }
        return Self.avatarFileName(forHash: hash)
    }

    static func avatarFileName(forHash hash: String) -> String {
        // All group avatars are PNGs, use the appropriate file extension.
        return "\(hash).png"
    }

    static func avatarFilePath(forHash hash: String) -> URL {
        URL(fileURLWithPath: avatarFileName(forHash: hash), relativeTo: avatarsDirectory)
    }

    class func allGroupAvatarFilePaths(transaction: SDSAnyReadTransaction) throws -> Set<String> {
        let cursor = TSThread.grdbFetchCursor(
            sql: "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .recordType) = \(SDSRecordType.groupThread.rawValue)",
            transaction: transaction.unwrapGrdbRead
        )

        var filePaths = Set<String>()

        while let thread = try cursor.next() as? TSGroupThread {
            guard let avatarHash = thread.groupModel.avatarHash else { continue }
            filePaths.insert(avatarFilePath(forHash: avatarHash).path)
        }

        return filePaths
    }
}

// MARK: -

extension TSGroupModel {
    static func generateRandomGroupId(_ version: GroupsVersion) -> Data {
        let length = switch version {
        case .V1: kGroupIdLengthV1
        case .V2: kGroupIdLengthV2
        }

        return Randomness.generateRandomBytes(length)
    }
}
