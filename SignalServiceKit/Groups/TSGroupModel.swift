//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
public import LibSignalClient

@objc
public class TSGroupModelV2: TSGroupModel {
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
    @objc
    public var descriptionText: String?

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
    public var avatarDataFailedToFetchFromCDN: Bool = false
    @objc
    public var lowTrustAvatarDownloadWasBlocked: Bool = false

    public init(
        groupId: Data,
        name: String?,
        descriptionText: String?,
        avatarDataState: AvatarDataState,
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
        addedByAddress: SignalServiceAddress?
    ) {
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

        let avatarData: Data?
        switch avatarDataState {
        case .available(let _avatarData):
            avatarData = _avatarData
        case .missing:
            avatarData = nil
        case .failedToFetchFromCDN:
            avatarData = nil
            avatarDataFailedToFetchFromCDN = true
        case .lowTrustDownloadWasBlocked:
            avatarData = nil
            lowTrustAvatarDownloadWasBlocked = true
        }

        super.init(
            groupId: groupId,
            name: name,
            avatarData: avatarData,
            members: [],
            addedBy: addedByAddress
        )
    }

    public func secretParams() throws -> GroupSecretParams {
        return try GroupSecretParams(contents: self.secretParamsData)
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
        contentsV1Builder.setGroupMasterKey(masterKey.serialize())
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

        let avatarHasUserFacingChange: Bool
        if avatarHash == otherGroupModel.avatarHash {
            avatarHasUserFacingChange = false
        } else if
            otherGroupModel.lowTrustAvatarDownloadWasBlocked,
            !self.lowTrustAvatarDownloadWasBlocked
        {
            // Avatar unblurred. No info message needed
            avatarHasUserFacingChange = false
        } else {
            avatarHasUserFacingChange = true
        }

        guard
            groupName == otherGroupModel.groupName,
            !avatarHasUserFacingChange,
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
        result += "descriptionText: \(String(describing: descriptionText)),\n"
        result += "]"
        return result
    }

    // MARK: -

    @objc
    public var groupInviteLinkMode: GroupsV2LinkMode {
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

    @objc
    public var isGroupInviteLinkEnabled: Bool {
        if let inviteLinkPassword = inviteLinkPassword,
           !inviteLinkPassword.isEmpty,
           access.canJoinFromInviteLink {
            return true
        }
        return false
    }
}

// MARK: -

extension TSGroupModel {
    @objc
    public var isPlaceholder: Bool {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return false
        }
        return groupModelV2.isJoinRequestPlaceholder
    }

    @objc
    public var wasJustMigratedToV2: Bool {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return false
        }
        return groupModelV2.wasJustMigrated
    }

    @objc
    public var didJustAddSelfViaGroupLinkV2: Bool {
        guard let groupModelV2 = self as? TSGroupModelV2 else {
            return false
        }
        return groupModelV2.didJustAddSelfViaGroupLink
    }

    // MARK: -

    private static let avatarsCache = LRUCache<String, Data>(maxSize: 16, nseMaxSize: 0)

    @objc
    public func persistAvatarData(_ data: Data) throws {
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

        try data.write(to: filePath)
        Self.avatarsCache.set(key: hash, value: data)

        // Note: Old avatars are explicitly not cleaned up from the file
        // system at this point, as multiple instances of a group model
        // may be floating around referencing different versions of
        // the avatar. We only purge old avatars from the file system
        // when orphan data cleaner deems it safe to do so.

        self.avatarHash = hash
    }

    private static let kMaxAvatarDimension = 1024

    public static func isValidGroupAvatarData(_ imageData: Data) -> Bool {
        guard imageData.count <= kMaxAvatarSize else {
            return false
        }
        guard let metadata = DataImageSource(imageData).imageMetadata() else {
            return false
        }
        return (
            metadata.pixelSize.height <= CGFloat(kMaxAvatarDimension)
            && metadata.pixelSize.width <= CGFloat(kMaxAvatarDimension)
        )
    }

    public static func dataForGroupAvatar(_ image: UIImage) -> Data? {
        var image = image

        // First, resize the image if necessary
        if image.pixelWidth > kMaxAvatarDimension || image.pixelHeight > kMaxAvatarDimension {
            let thumbnailSizePixels = min(kMaxAvatarDimension, min(image.pixelWidth, image.pixelHeight))
            image = image.resizedImage(toFillPixelSize: CGSize(width: thumbnailSizePixels, height: thumbnailSizePixels))
        }
        if image.pixelWidth > kMaxAvatarDimension || image.pixelHeight > kMaxAvatarDimension {
            owsFailDebug("Could not resize group avatar.")
            return nil
        }

        // Then, convert the image to jpeg. Try to use 0.6 compression quality, but we'll ratchet down if the
        // image is still too large.
        let kMaxQuality = 0.6 as CGFloat
        for targetQuality in stride(from: kMaxQuality, through: 0, by: -0.1) {
            let avatarData = image.jpegData(compressionQuality: targetQuality)

            guard let avatarData else {
                owsFailDebug("Failed to generate jpeg representation with quality \(targetQuality)")
                return nil
            }

            if avatarData.count <= kMaxAvatarSize {
                guard isValidGroupAvatarData(avatarData) else {
                    owsFailDebug("Invalid image")
                    return nil
                }
                return avatarData
            }
        }
        owsFailDebug("All quality levels produced an avatar that was too large")
        return nil
    }

    // MARK: -

    public enum AvatarDataState {
        case available(Data)
        case missing
        case failedToFetchFromCDN
        case lowTrustDownloadWasBlocked

        init(avatarData: Data?) {
            if let avatarData {
                self = .available(avatarData)
            } else {
                self = .missing
            }
        }

        public var dataIfPresent: Data? {
            switch self {
            case .available(let data): return data
            default: return nil
            }
        }
    }

    public var avatarDataState: AvatarDataState {
        if let selfAsV2 = self as? TSGroupModelV2 {
            if selfAsV2.avatarDataFailedToFetchFromCDN {
                return .failedToFetchFromCDN
            }
            if selfAsV2.lowTrustAvatarDownloadWasBlocked {
                return .lowTrustDownloadWasBlocked
            }
        }

        if let dataFromDisk = readAvatarDataFromDisk() {
            return .available(dataFromDisk)
        } else {
            return .missing
        }
    }

    /// Reads the data for this group's avatar from disk. Only present if an
    /// `avatarUrlPath` is also present, and the data from that URL was
    /// successfully fetched and determined to be valid.
    private func readAvatarDataFromDisk() -> Data? {
        guard let avatarHash else {
            // We write this when we persist data, so if it's missing we don't
            // have persisted data.
            return nil
        }

        if let cachedData = Self.avatarsCache.object(forKey: avatarHash) {
            return cachedData
        }

        let avatarData: Data
        do {
            let filePath = Self.avatarFilePath(forHash: avatarHash)
            avatarData = try Data(contentsOf: filePath)
        } catch {
            owsFailDebug("Failed to read group avatar data \(error)")
            return nil
        }

        guard DataImageSource(avatarData).ows_isValidImage else {
            owsFailDebug("Invalid group avatar data.")
            return nil
        }

        return avatarData
    }

    // MARK: -

    private static func avatarFilePath(forHash hash: String) -> URL {
        return URL(fileURLWithPath: "\(hash).png", relativeTo: avatarsDirectory)
    }

    public static let avatarsDirectory = URL(
        fileURLWithPath: "GroupAvatars",
        isDirectory: true,
        relativeTo: URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
    )

    public static func hash(forAvatarData avatarData: Data) throws -> String {
        return Data(SHA256.hash(data: avatarData)).hexadecimalString
    }

    public static func allGroupAvatarFilePaths(transaction: DBReadTransaction) throws -> Set<String> {
        let cursor = TSThread.grdbFetchCursor(
            sql: "SELECT * FROM \(ThreadRecord.databaseTableName) WHERE \(threadColumn: .recordType) = \(SDSRecordType.groupThread.rawValue)",
            transaction: transaction
        )

        var filePaths = Set<String>()

        do {
            while let thread = try cursor.next() as? TSGroupThread {
                guard let avatarHash = thread.groupModel.avatarHash else { continue }
                filePaths.insert(avatarFilePath(forHash: avatarHash).path)
            }
        } catch {
            throw error.grdbErrorForLogging
        }

        return filePaths
    }

    // MARK: -

    static func generateRandomGroupId(_ version: GroupsVersion) -> Data {
        let length = switch version {
        case .V1: kGroupIdLengthV1
        case .V2: kGroupIdLengthV2
        }

        return Randomness.generateRandomBytes(length)
    }
}
