//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
    // We sometimes create "placeholder" models to reflect
    // groups that we don't have access to on the service.
    @objc
    public var isPlaceholderModel: Bool = false
    @objc
    public var wasJustMigrated: Bool = false
    @objc
    public var didJustAddSelfViaGroupLink: Bool = false
    @objc
    public var droppedMembers = [SignalServiceAddress]()
    @objc
    public var descriptionText: String?

    @objc
    public required init(groupId: Data,
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
                         isPlaceholderModel: Bool,
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
        self.isPlaceholderModel = isPlaceholderModel
        self.wasJustMigrated = wasJustMigrated
        self.didJustAddSelfViaGroupLink = didJustAddSelfViaGroupLink
        self.droppedMembers = droppedMembers

        super.init(groupId: groupId,
                   name: name,
                   avatarData: avatarData,
                   members: [],
                   addedBy: addedByAddress)
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
                return descriptionText == nil
            }
        }
        guard other.descriptionText == descriptionText else {
            return false
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
        guard other.isAnnouncementsOnly == isAnnouncementsOnly else {
            return false
        }
        guard other.droppedMembers.stableSort() == droppedMembers.stableSort() else {
            return false
        }
        // Ignore transient properties:
        //
        // * isPlaceholderModel
        // * wasJustMigrated
        // * didJustAddSelfViaGroupLink
        return true
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
        result += "isPlaceholderModel: \(isPlaceholderModel),\n"
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
        return groupModelV2.isPlaceholderModel
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
        guard let digest = Cryptography.computeSHA256Digest(avatarData) else {
            throw OWSAssertionError("Unexpectedly failed to calculate avatar digest")
        }

        return digest.hexadecimalString
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
