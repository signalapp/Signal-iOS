//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

@objc
public class OWSUserProfileBadgeInfo: NSObject, Codable {
    @objc
    public let badgeId: String

    /// Details about how to render `badgeId`.
    ///
    /// Nil until a call to `loadBadge()` or `fetchBadgeContent(transaction:)`.
    public var badge: ProfileBadge?

    /// When the badge expires.
    ///
    /// Nil unless this is a badge for the local user.
    public let expiration: UInt64?

    /// True if the badge is visible.
    ///
    /// Nil unless this is a badge for the local user. (For other users, we only
    /// learn about visible badges, so we assume they're all visible.)
    public let isVisible: Bool?

    init(badgeId: String) {
        self.badgeId = badgeId
        self.expiration = nil
        self.isVisible = nil
    }

    init(badgeId: String, expiration: UInt64, isVisible: Bool) {
        self.badgeId = badgeId
        self.expiration = expiration
        self.isVisible = isVisible
    }

    private enum CodingKeys: String, CodingKey {
        // Skip encoding of the actual badge content
        case badgeId, expiration, isVisible
    }

    @objc
    public func loadBadge(transaction: SDSAnyReadTransaction) {
        badge = SSKEnvironment.shared.profileManagerRef.badgeStore.fetchBadgeWithId(badgeId, readTx: transaction)
    }

    @objc
    public func fetchBadgeContent(transaction: SDSAnyReadTransaction) -> ProfileBadge? {
        return badge ?? {
            loadBadge(transaction: transaction)
            return badge
        }()
    }

    override public var description: String {
        var description = "Badge: \(badgeId)"
        if let expiration = expiration {
            description += ", Expires: \(Date(millisecondsSince1970: expiration))"
        }
        if let isVisible = isVisible {
            description += ", Visible: \(isVisible ? "Yes" : "No")"
        }
        return description
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? OWSUserProfileBadgeInfo else {
            return false
        }
        if badgeId != other.badgeId {
            return false
        }
        // NOTE: We do not compare badges because the badgeId is good enough for equality purposes.
        if expiration != other.expiration {
            return false
        }
        if isVisible != other.isVisible {
            return false
        }
        return true
    }
}

extension UserProfileWriter {
    var shouldUpdateStorageService: Bool {
        switch self {
        case .changePhoneNumber: fallthrough
        case .groupState: fallthrough
        case .localUser: fallthrough
        case .profileFetch: fallthrough
        case .registration: fallthrough
        case .reupload: fallthrough
        case .systemContactsFetch:
            return true

        case .avatarDownload: fallthrough
        case .debugging: fallthrough
        case .linking: fallthrough
        case .messageBackupRestore: fallthrough
        case .metadataUpdate: fallthrough
        case .storageService: fallthrough
        case .syncMessage: fallthrough
        case .tests:
            return false

        case .unknown: fallthrough
        @unknown default:
            return false
        }
    }
}

@objc
public final class UserProfileNotifications: NSObject {
    @objc
    public static let profileWhitelistDidChange = Notification.Name("kNSNotificationNameProfileWhitelistDidChange")

    @objc
    public static let localProfileDidChange = Notification.Name("kNSNotificationNameLocalProfileDidChange")

    @objc
    public static let localProfileKeyDidChange = Notification.Name("kNSNotificationNameLocalProfileKeyDidChange")

    @objc
    public static let otherUsersProfileDidChange = Notification.Name("kNSNotificationNameOtherUsersProfileDidChange")

    @objc
    public static let profileAddressKey = "kNSNotificationKey_ProfileAddress"

    @objc
    public static let profileGroupIdKey = "kNSNotificationKey_ProfileGroupId"
}

@objc
public final class OWSUserProfile: NSObject, NSCopying, SDSCodableModel, Decodable {
    public static let databaseTableName = "model_OWSUserProfile"
    public static var recordType: UInt { SDSRecordType.userProfile.rawValue }

    /// An address used to identify an ``OWSUserProfile``.
    public enum Address: Hashable {
        case localUser
        case otherUser(SignalServiceAddress)
    }

    /// An address used to insert or update an ``OWSUserProfile``.
    public enum InsertableAddress {
        case localUser
        case otherUser(ServiceId)
        /// Describes a legacy user for whom no service ID is available, found
        /// while restoring from a backup.
        case legacyUserPhoneNumberFromBackupRestore(E164)
    }

    // MARK: - Constants

    public enum Constants {
        // For these values, "glyphs" represent what the user should be able to
        // type in an ideal world (eg "your name can contain 26 characters").
        // "Bytes" represents what the server enforces. Note that it's possible to
        // run into either limit (eg 5 emoji might hit the byte limit and 26 ASCII
        // characters might hit the glyph limit).

        public static let maxNameLengthGlyphs: Int = 26
        public static let maxNameLengthBytes: Int = 128

        public static let maxBioLengthGlyphs: Int = 140
        public static let maxBioLengthBytes: Int = 512

        fileprivate static let maxBioEmojiLengthGlyphs: Int = 1
        fileprivate static let maxBioEmojiLengthBytes: Int = 32

        static let localProfilePhoneNumber = "kLocalProfileUniqueId"
    }

    // MARK: - Properties

    public var id: RowId?
    public let uniqueId: String

    public var serviceIdString: String?
    public var phoneNumber: String?

    public var serviceId: ServiceId? { serviceIdString.flatMap { try? ServiceId.parseFrom(serviceIdString: $0) } }

    /// The "internal" address.
    ///
    /// The local user is represented by `localProfilePhoneNumber` and no ACI.
    /// All other users are represented by their real ACI/E164/PNI addresses.
    public var internalAddress: Address {
        if phoneNumber == Constants.localProfilePhoneNumber {
            return .localUser
        } else {
            return .otherUser(SignalServiceAddress.legacyAddress(serviceIdString: serviceIdString, phoneNumber: phoneNumber))
        }
    }

    /// The "public" address.
    ///
    /// All users are represented by their real ACI/PNI/E164 addresses.
    public func publicAddress(localIdentifiers: LocalIdentifiers) -> SignalServiceAddress {
        return Self.publicAddress(for: internalAddress, localIdentifiers: localIdentifiers)
    }

    /// The on-disk location of the downloaded avatar.
    ///
    /// This filename is relative to `profileAvatarsDirPath`.
    @objc
    private(set) public var avatarFileName: String?

    /// The on-server location of the encrypted avatar.
    ///
    /// This URL is downloaded, decrypted, and saved to `avatarFileName`.
    @objc
    private(set) public var avatarUrlPath: String?

    @objc
    private(set) public var profileKey: Aes256Key?

    @objc
    private(set) public var givenName: String?

    @objc
    private(set) public var familyName: String?

    @objc
    private(set) public var bio: String?

    @objc
    private(set) public var bioEmoji: String?

    @objc
    private(set) public var badges: [OWSUserProfileBadgeInfo]

    /// The last time we fetched a profile for this user.
    private(set) public var lastFetchDate: Date?

    /// This field reflects the last time we sent or received a message from
    /// this user. It is coarse; we only update it when it changes by more than
    /// one hour. It's not updated when sending messages to the local user
    /// (because we fetch our own profile more frequently than we fetch the
    /// profiles of other users).
    @objc
    private(set) public var lastMessagingDate: Date?

    /// Stores whether or not the phone number is shared for this account.
    ///
    /// Note that we may not yet know a phone number that's shared (and vice
    /// versa). If the value is nil, then it means there's not a value, we've
    /// never had a profile key for this user, or the value can't be decrypted.
    private(set) public var isPhoneNumberShared: Bool?

    public convenience init(
        address: Address,
        givenName: String? = nil,
        familyName: String? = nil,
        profileKey: Aes256Key? = nil,
        avatarUrlPath: String? = nil
    ) {
        let serviceId: ServiceId?
        let phoneNumber: String?
        switch address {
        case .localUser:
            serviceId = nil
            phoneNumber = Constants.localProfilePhoneNumber
        case .otherUser(let address):
            let normalizedAddress = NormalizedDatabaseRecordAddress(address: address)
            serviceId = normalizedAddress?.serviceId
            phoneNumber = normalizedAddress?.phoneNumber
        }
        self.init(
            id: nil,
            uniqueId: UUID().uuidString,
            serviceIdString: serviceId?.serviceIdUppercaseString,
            phoneNumber: phoneNumber,
            avatarFileName: nil,
            avatarUrlPath: avatarUrlPath,
            profileKey: profileKey,
            givenName: givenName,
            familyName: familyName,
            bio: nil,
            bioEmoji: nil,
            badges: [],
            lastFetchDate: nil,
            lastMessagingDate: nil,
            isPhoneNumberShared: nil
        )
    }

    init(
        id: RowId?,
        uniqueId: String,
        serviceIdString: String?,
        phoneNumber: String?,
        avatarFileName: String?,
        avatarUrlPath: String?,
        profileKey: Aes256Key?,
        givenName: String?,
        familyName: String?,
        bio: String?,
        bioEmoji: String?,
        badges: [OWSUserProfileBadgeInfo],
        lastFetchDate: Date?,
        lastMessagingDate: Date?,
        isPhoneNumberShared: Bool?
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.serviceIdString = serviceIdString
        self.phoneNumber = phoneNumber
        self.avatarFileName = avatarFileName
        self.avatarUrlPath = avatarUrlPath
        self.profileKey = profileKey
        self.givenName = givenName
        self.familyName = familyName
        self.bio = bio
        self.bioEmoji = bioEmoji
        self.badges = badges
        self.lastFetchDate = lastFetchDate
        self.lastMessagingDate = lastMessagingDate
        self.isPhoneNumberShared = isPhoneNumberShared
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return shallowCopy()
    }

    @objc
    public func shallowCopy() -> OWSUserProfile {
        return OWSUserProfile(
            id: id,
            uniqueId: uniqueId,
            serviceIdString: serviceIdString,
            phoneNumber: phoneNumber,
            avatarFileName: avatarFileName,
            avatarUrlPath: avatarUrlPath,
            profileKey: profileKey,
            givenName: givenName,
            familyName: familyName,
            bio: bio,
            bioEmoji: bioEmoji,
            badges: badges,
            lastFetchDate: lastFetchDate,
            lastMessagingDate: lastMessagingDate,
            isPhoneNumberShared: isPhoneNumberShared
        )
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherProfile = object as? OWSUserProfile else {
            return false
        }
        guard id == otherProfile.id else { return false }
        guard uniqueId == otherProfile.uniqueId else { return false }
        guard serviceIdString == otherProfile.serviceIdString else { return false }
        guard phoneNumber == otherProfile.phoneNumber else { return false }
        guard avatarFileName == otherProfile.avatarFileName else { return false }
        guard avatarUrlPath == otherProfile.avatarUrlPath else { return false }
        guard profileKey == otherProfile.profileKey else { return false }
        guard givenName == otherProfile.givenName else { return false }
        guard familyName == otherProfile.familyName else { return false }
        guard bio == otherProfile.bio else { return false }
        guard bioEmoji == otherProfile.bioEmoji else { return false }
        guard badges == otherProfile.badges else { return false }
        guard lastFetchDate == otherProfile.lastFetchDate else { return false }
        guard lastMessagingDate == otherProfile.lastMessagingDate else { return false }
        guard isPhoneNumberShared == otherProfile.isPhoneNumberShared else { return false }
        return true
    }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case avatarFileName
        case avatarUrlPath
        case profileKey
        case givenName = "profileName"
        case phoneNumber = "recipientPhoneNumber"
        case serviceIdString = "recipientUUID"
        case familyName
        case lastFetchDate
        case lastMessagingDate
        case bio
        case bioEmoji
        case badges = "profileBadgeInfo"
        case isStoriesCapable
        case canReceiveGiftBadges
        case isPniCapable
        case isPhoneNumberShared
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encodeIfPresent(serviceIdString, forKey: .serviceIdString)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encodeIfPresent(avatarFileName, forKey: .avatarFileName)
        try container.encodeIfPresent(avatarUrlPath, forKey: .avatarUrlPath)
        try container.encodeIfPresent(profileKey?.keyData, forKey: .profileKey)
        try container.encodeIfPresent(givenName, forKey: .givenName)
        try container.encodeIfPresent(familyName, forKey: .familyName)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(bioEmoji, forKey: .bioEmoji)
        try container.encode(JSONEncoder().encode(badges), forKey: .badges)
        try container.encodeIfPresent(lastFetchDate, forKey: .lastFetchDate)
        try container.encodeIfPresent(lastMessagingDate, forKey: .lastMessagingDate)
        try container.encode(true, forKey: .isStoriesCapable)
        try container.encode(true, forKey: .canReceiveGiftBadges)
        try container.encode(true, forKey: .isPniCapable)
        try container.encodeIfPresent(isPhoneNumberShared, forKey: .isPhoneNumberShared)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(UInt.self, forKey: .recordType)
        guard decodedRecordType == Self.recordType else {
            owsFailDebug("Unexpected record type: \(decodedRecordType)")
            throw SDSError.invalidValue()
        }

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        serviceIdString = try container.decodeIfPresent(String.self, forKey: .serviceIdString)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        avatarFileName = try container.decodeIfPresent(String.self, forKey: .avatarFileName)
        avatarUrlPath = try container.decodeIfPresent(String.self, forKey: .avatarUrlPath)
        profileKey = try container.decodeIfPresent(Data.self, forKey: .profileKey).map(Self.decodeProfileKey(_:))
        givenName = try container.decodeIfPresent(String.self, forKey: .givenName)
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        bioEmoji = try container.decodeIfPresent(String.self, forKey: .bioEmoji)
        badges = try container.decodeIfPresent(Data.self, forKey: .badges).map {
            try JSONDecoder().decode([OWSUserProfileBadgeInfo].self, from: $0)
        } ?? []
        lastFetchDate = try container.decodeIfPresent(Date.self, forKey: .lastFetchDate)
        lastMessagingDate = try container.decodeIfPresent(Date.self, forKey: .lastMessagingDate)
        isPhoneNumberShared = try container.decodeIfPresent(Bool.self, forKey: .isPhoneNumberShared)
    }

    private static func decodeProfileKey(_ profileKeyData: Data) throws -> Aes256Key {
        guard profileKeyData.count == Aes256Key.keyByteLength, let profileKey = Aes256Key(data: profileKeyData) else {
            // Historically, we encoded this using an NSKeyedArchiver. We assume it's
            // encoded in this way if it's not exactly 32 bytes.
            return try LegacySDSSerializer().deserializeLegacySDSData(profileKeyData, propertyName: "profileKey")
        }
        return profileKey
    }

    // MARK: -

    /// Converts a "public" address to an "internal" one.
    public static func internalAddress(for publicAddress: SignalServiceAddress, localIdentifiers: LocalIdentifiers) -> Address {
        if localIdentifiers.contains(address: publicAddress) {
            return .localUser
        } else {
            return .otherUser(publicAddress)
        }
    }

    /// Converts an "internal" or "public" address to a "public" one.
    private static func publicAddress(for internalAddress: Address, localIdentifiers: LocalIdentifiers) -> SignalServiceAddress {
        switch internalAddress {
        case .localUser:
            return localIdentifiers.aciAddress
        case .otherUser(let address):
            return address
        }
    }

    // MARK: -

    static func insertableAddress(
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers
    ) -> InsertableAddress {
        if localIdentifiers.contains(serviceId: serviceId) {
            return .localUser
        }

        return .otherUser(serviceId)
    }

    static func insertableAddress(
        legacyPhoneNumberFromBackupRestore phoneNumber: E164,
        localIdentifiers: LocalIdentifiers
    ) -> InsertableAddress {
        if localIdentifiers.contains(phoneNumber: phoneNumber) {
            return .localUser
        }

        return .legacyUserPhoneNumberFromBackupRestore(phoneNumber)
    }

    // MARK: - Avatar

    /// Updates the remote/local avatar path properties.
    ///
    /// If you specify a new `avatarFileName` (ie the local path), the file
    /// specified by the old value is deleted from the disk.
    ///
    /// If you specify a new `avatarUrlPath` (ie the remote URL) without
    /// specifying its corresponding `avatarFileName` (ie the local path), then
    /// `avatarFileName` is cleared and the existing file is deleted.
    private func updateAvatar(avatarUrlPath: OptionalChange<String?>, avatarFileName: OptionalChange<String?>) -> Bool {
        let oldAvatarUrlPath = self.avatarUrlPath
        let newAvatarUrlPath = avatarUrlPath.orExistingValue(oldAvatarUrlPath)
        let urlPathDidChange = oldAvatarUrlPath != newAvatarUrlPath

        let oldAvatarFileName = self.avatarFileName
        // If we're changing avatarUrlPath, we must provide a new avatarFileName.
        // If we don't, we use `nil` to delete the existing one that's wrong.
        let newAvatarFileName = avatarFileName.orExistingValue(urlPathDidChange ? nil : oldAvatarFileName)
        let fileNameDidChange = oldAvatarFileName != newAvatarFileName

        guard urlPathDidChange || fileNameDidChange else {
            return false
        }

        if fileNameDidChange, let oldAvatarFileName, !oldAvatarFileName.isEmpty {
            let oldAvatarFilePath = Self.profileAvatarFilePath(for: oldAvatarFileName)
            OWSFileSystem.deleteFileIfExists(oldAvatarFilePath)
        }

        self.avatarUrlPath = newAvatarUrlPath
        self.avatarFileName = newAvatarFileName
        return true
    }

    /// Moves a temporary avatar file into its permanent location.
    ///
    /// This method accepts a `tx` parameter to ensure that this move occurs
    /// within a write transaction. Callers must ensure that it's the same write
    /// transaction that assigns the result to an OWSUserProfile. In doing so,
    /// callers ensure that the orphaned cleanup logic doesn't delete avatars
    /// that are about to be referenced.
    static func consumeTemporaryAvatarFileUrl(
        _ avatarFileUrl: OptionalChange<URL?>,
        tx: SDSAnyWriteTransaction
    ) throws -> OptionalChange<String?> {
        switch avatarFileUrl {
        case .noChange:
            return .noChange
        case .setTo(.none):
            return .setTo(nil)
        case .setTo(.some(let temporaryFileUrl)):
            let filename = generateAvatarFilename()
            let filePath = profileAvatarFilePath(for: filename)
            try FileManager.default.moveItem(atPath: temporaryFileUrl.path, toPath: filePath)
            return .setTo(filename)
        }
    }

    @objc
    public static var legacyProfileAvatarsDirPath: String {
        return OWSFileSystem.appDocumentDirectoryPath().appendingPathComponent("ProfileAvatars")
    }

    @objc
    public static var sharedDataProfileAvatarsDirPath: String {
        return OWSFileSystem.appSharedDataDirectoryPath().appendingPathComponent("ProfileAvatars")
    }

    private static let profileAvatarsDirPath: String = {
        let result = sharedDataProfileAvatarsDirPath
        OWSFileSystem.ensureDirectoryExists(result)
        return result
    }()

    static func generateAvatarFilename() -> String {
        return UUID().uuidString + ".jpg"
    }

    @objc
    static func profileAvatarFilePath(for filename: String) -> String {
        owsAssertDebug(!filename.isEmpty)
        return Self.profileAvatarsDirPath.appendingPathComponent(filename)
    }

    // TODO: We may want to clean up this directory in the "orphan cleanup" logic.

    @objc
    public static func allProfileAvatarFilePaths(tx: SDSAnyReadTransaction) -> Set<String> {
        var result = Set<String>()
        Self.anyEnumerate(transaction: tx, batchingPreference: .batched(Batching.kDefaultBatchSize)) { userProfile, _ in
            if let avatarFileName = userProfile.avatarFileName {
                result.insert(Self.profileAvatarsDirPath.appendingPathComponent(avatarFileName))
            }
        }
        return result
    }

    // MARK: - Badges

    public var visibleBadges: [OWSUserProfileBadgeInfo] {
        return badges.filter { $0.isVisible ?? true }
    }

    public var primaryBadge: OWSUserProfileBadgeInfo? {
        return visibleBadges.first
    }

    func loadBadgeContent(tx: SDSAnyReadTransaction) {
        badges.forEach({ $0.loadBadge(transaction: tx) })
    }

    // MARK: - Bio

    private static let bioComponentCache = LRUCache<String, String>(maxSize: 256)
    private static let unfairLock = UnfairLock()

    private static func filterBioComponentForDisplay(_ input: String?, maxLengthGlyphs: Int, maxLengthBytes: Int) -> String? {
        guard let input = input else {
            return nil
        }
        let cacheKey = "\(maxLengthGlyphs)-\(maxLengthBytes)-\(input)"
        return unfairLock.withLock {
            // Note: we use empty strings in the cache, but return nil for empty strings.
            if let cachedValue = bioComponentCache.get(key: cacheKey) {
                return cachedValue.nilIfEmpty
            }
            let value = input.filterStringForDisplay().trimToGlyphCount(maxLengthGlyphs).trimToUtf8ByteCount(maxLengthBytes)
            bioComponentCache.set(key: cacheKey, value: value)
            return value.nilIfEmpty
        }
    }

    /// Joins the two bio components into a single string ready for display. It
    /// filters and enforces length limits on the components.
    @objc
    public static func bioForDisplay(bio: String?, bioEmoji: String?) -> String? {
        var components = [String]()
        // TODO: We could use EmojiWithSkinTones to check for availability of the emoji.
        if let emoji = filterBioComponentForDisplay(
            bioEmoji,
            maxLengthGlyphs: Constants.maxBioEmojiLengthGlyphs,
            maxLengthBytes: Constants.maxBioEmojiLengthBytes
        ) {
            components.append(emoji)
        }
        if let bioText = filterBioComponentForDisplay(
            bio,
            maxLengthGlyphs: Constants.maxBioLengthGlyphs,
            maxLengthBytes: Constants.maxBioLengthBytes
        ) {
            components.append(bioText)
        }
        guard !components.isEmpty else {
            return nil
        }
        return components.joined(separator: " ")
    }

    // MARK: - Name

    public var nameComponents: PersonNameComponents? {
        guard let givenName = self.givenName?.strippedOrNil else {
            return nil
        }
        var result = PersonNameComponents()
        result.givenName = givenName
        result.familyName = self.familyName?.strippedOrNil
        return result
    }

    @objc
    public var filteredGivenName: String? { givenName?.filterForDisplay }

    @objc
    public var filteredFamilyName: String? { familyName?.filterForDisplay }

    @objc
    public var filteredNameComponents: PersonNameComponents? {
        guard let givenName = self.filteredGivenName?.nilIfEmpty else {
            return nil
        }
        var result = PersonNameComponents()
        result.givenName = givenName
        result.familyName = self.filteredFamilyName
        return result
    }

    @objc
    public var filteredFullName: String? {
        return filteredNameComponents.map(OWSFormat.formatNameComponents(_:))?.filterForDisplay
    }

    // MARK: - Encryption

    public class func encrypt(profileData: Data, profileKey: Aes256Key) throws -> Data {
        return try Aes256GcmEncryptedData.encrypt(profileData, key: profileKey.keyData).concatenate()
    }

    public class func decrypt(profileData: Data, profileKey: ProfileKey) throws -> Data {
        return try Aes256GcmEncryptedData(concatenated: profileData).decrypt(key: profileKey.serialize().asData)
    }

    enum DecryptionError: Error {
        case missingName
        case malformedValue
    }

    class func decrypt(profileNameData: Data, profileKey: ProfileKey) throws -> (givenName: String, familyName: String?) {
        let decryptedData = try decrypt(profileData: profileNameData, profileKey: profileKey)

        func parseNameSegment(_ nameSegment: Data) throws -> String? {
            guard let nameValue = String(data: nameSegment, encoding: .utf8) else {
                throw DecryptionError.malformedValue
            }
            return nameValue.strippedOrNil
        }

        // Unpad profile name. The given and family name are stored in the string
        // like "<given name><null><family name><null padding>"
        let nameSegments: [Data] = decryptedData.split(separator: 0x00, maxSplits: 2, omittingEmptySubsequences: false)

        guard let givenName = try parseNameSegment(nameSegments.first!) else {
            throw DecryptionError.missingName
        }
        let familyName = nameSegments.dropFirst().first
        return (givenName, try familyName.flatMap(parseNameSegment(_:)))
    }

    class func decrypt(profileStringData: Data, profileKey: ProfileKey) throws -> String? {
        let decryptedData = try decrypt(profileData: profileStringData, profileKey: profileKey)

        // Remove padding.
        let segments: [Data] = decryptedData.split(separator: 0x00, maxSplits: 1, omittingEmptySubsequences: false)
        guard let value = String(data: segments.first!, encoding: .utf8) else {
            throw DecryptionError.malformedValue
        }
        return value.nilIfEmpty
    }

    class func decrypt(profileBooleanData: Data, profileKey: ProfileKey) throws -> Bool {
        switch try decrypt(profileData: profileBooleanData, profileKey: profileKey) {
        case Data([1]):
            return true
        case Data([0]):
            return false
        default:
            throw DecryptionError.malformedValue
        }
    }

    public class func encrypt(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        profileKey: Aes256Key
    ) throws -> ProfileValue {
        let encodedValues: [Data] = [givenName.dataValue, familyName?.dataValue].compacted()
        let encodedValue = Data(encodedValues.joined(separator: Data([0])))
        assert(Constants.maxNameLengthBytes * 2 + 1 == 257)
        return try encrypt(data: encodedValue, profileKey: profileKey, paddedLengths: [53, 257])
    }

    public class func encrypt(data unpaddedData: Data, profileKey: Aes256Key, paddedLengths: [Int]) throws -> ProfileValue {
        assert(paddedLengths == paddedLengths.sorted())

        guard let paddedLength = paddedLengths.first(where: { $0 >= unpaddedData.count }) else {
            throw OWSAssertionError("Oversize value: \(unpaddedData.count) > \(paddedLengths)")
        }

        var paddedData = unpaddedData
        let paddingByteCount = paddedLength - paddedData.count
        paddedData.count += paddingByteCount
        assert(paddedData.count == paddedLength)

        return ProfileValue(encryptedData: try encrypt(profileData: paddedData, profileKey: profileKey))
    }

    // MARK: - Fetching & Creating

    @objc
    public static func getUserProfileForLocalUser(tx: SDSAnyReadTransaction) -> OWSUserProfile? {
        return getUserProfile(for: .localUser, tx: tx)
    }

    public static func getUserProfile(for address: Address, tx: SDSAnyReadTransaction) -> OWSUserProfile? {
        return UserProfileFinder().userProfile(for: address, transaction: tx)
    }

    @objc
    public static func doesLocalProfileExist(transaction tx: SDSAnyReadTransaction) -> Bool {
        return UserProfileFinder().userProfile(for: .localUser, transaction: tx) != nil
    }

    public class func getOrBuildUserProfileForLocalUser(
        userProfileWriter: UserProfileWriter,
        tx: SDSAnyWriteTransaction
    ) -> OWSUserProfile {
        return getOrBuildUserProfile(
            for: .localUser,
            userProfileWriter: userProfileWriter,
            tx: tx
        )
    }

    public class func getOrBuildUserProfile(
        for insertableAddress: InsertableAddress,
        userProfileWriter: UserProfileWriter,
        tx: SDSAnyWriteTransaction
    ) -> OWSUserProfile {
        // If we already have a profile for this address, return it.
        if let userProfile = fetchAndExpungeUserProfiles(for: insertableAddress, tx: tx) {
            return userProfile
        }

        let address: Address
        switch insertableAddress {
        case .localUser:
            address = .localUser
        case .otherUser(let serviceId):
            address = .otherUser(SignalServiceAddress(serviceId))
        case .legacyUserPhoneNumberFromBackupRestore(let phoneNumber):
            address = .otherUser(SignalServiceAddress(phoneNumber: phoneNumber.stringValue))
        }

        // Otherwise, create & return a new profile for this address.
        let userProfile = OWSUserProfile(address: address)
        if case .localUser = address {
            userProfile.update(
                profileKey: .setTo(Aes256Key.generateRandom()),
                userProfileWriter: userProfileWriter,
                transaction: tx,
                completion: nil
            )
        }
        return userProfile
    }

    /// Ensures there's a single profile for a given recipient.
    ///
    /// We should only have one UserProfile for each SignalRecipient. However,
    /// it's possible that duplicates may exist. This method will find and
    /// remove duplicates.
    private class func fetchAndExpungeUserProfiles(
        for insertableAddress: InsertableAddress,
        tx: SDSAnyWriteTransaction
    ) -> OWSUserProfile? {
        let userProfiles: [OWSUserProfile]
        switch insertableAddress {
        case .localUser:
            userProfiles = UserProfileFinder().fetchUserProfiles(phoneNumber: Constants.localProfilePhoneNumber, tx: tx)
        case .otherUser(let serviceId):
            userProfiles = UserProfileFinder().fetchUserProfiles(serviceId: serviceId, tx: tx)
        case .legacyUserPhoneNumberFromBackupRestore(let phoneNumber):
            userProfiles = UserProfileFinder().fetchUserProfiles(phoneNumber: phoneNumber.stringValue, tx: tx)
        }

        // Get rid of any duplicates -- these shouldn't exist.
        for redundantProfile in userProfiles.dropFirst() {
            redundantProfile.anyRemove(transaction: tx)
        }
        return userProfiles.first
    }

    // MARK: - Database Hooks

    public func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    public func anyDidInsert(transaction: SDSAnyWriteTransaction) {
        let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
        searchableNameIndexer.insert(self, tx: transaction.asV2Write)
    }

    public func anyDidUpdate(transaction: SDSAnyWriteTransaction) {
        let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
        searchableNameIndexer.update(self, tx: transaction.asV2Write)
    }

    // MARK: - ObjC Compability

    public static func shouldUpdateStorageServiceForUserProfileWriter(_ userProfileWriter: UserProfileWriter) -> Bool {
        return userProfileWriter.shouldUpdateStorageService
    }
}

// MARK: -

extension OWSUserProfile {
    public struct NameComponent: Equatable {
        public let stringValue: StrippedNonEmptyString
        public let dataValue: Data

        private init(stringValue: StrippedNonEmptyString, dataValue: Data) {
            self.stringValue = stringValue
            self.dataValue = dataValue
        }

        public init?(truncating: String) {
            guard let (parsedValue, _) = Self.parse(truncating: truncating) else {
                return nil
            }
            self = parsedValue
        }

        public static func parse(truncating: String) -> (nameComponent: Self, didTruncate: Bool)? {
            // We need to truncate to the required limit. Before doing so, we strip the
            // string in case there's any leading whitespace. For example, if the limit
            // is 3 characters, " Alice" should become "Ali" instead of "Al".
            let strippedString = truncating.stripped
            let truncatedString = strippedString
                .trimToGlyphCount(OWSUserProfile.Constants.maxNameLengthGlyphs)
                .trimToUtf8ByteCount(OWSUserProfile.Constants.maxNameLengthBytes)
            // After trimming, we need to strip AGAIN. If the string starts with a
            // control character, has a series of whitespaces, and then has
            // user-visible characters, and if we truncate those user visible
            // characters, we'll be left with a value that's now considered empty.
            guard let strippedTruncatedString = StrippedNonEmptyString(rawValue: truncatedString) else {
                return nil
            }
            guard let dataValue = strippedTruncatedString.rawValue.data(using: .utf8) else {
                return nil
            }
            return (
                NameComponent(stringValue: strippedTruncatedString, dataValue: dataValue),
                didTruncate: truncatedString != strippedString
            )
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            // Don't check `dataValue` because it's essentially a computed property.
            return lhs.stringValue == rhs.stringValue
        }
    }
}

// MARK: -

public struct ProfileValue {
    let encryptedData: Data

    public init(encryptedData: Data) {
        self.encryptedData = encryptedData
    }

    var encryptedBase64Value: String {
        encryptedData.base64EncodedString()
    }
}

// MARK: -

private struct UserProfileChanges {
    var givenName: OptionalChange<String?>
    var familyName: OptionalChange<String?>
    var bio: OptionalChange<String?>
    var bioEmoji: OptionalChange<String?>
    var avatarUrlPath: OptionalChange<String?>
    var avatarFileName: OptionalChange<String?>
    var lastFetchDate: OptionalChange<Date>
    var lastMessagingDate: OptionalChange<Date>
    var profileKey: OptionalChange<Aes256Key>
    var badges: OptionalChange<[OWSUserProfileBadgeInfo]>
    var isPhoneNumberShared: OptionalChange<Bool?>
}

// MARK: - Update With... Methods

extension OWSUserProfile {
    private enum UserVisibleChange {
        /// *Something* -- the profile name, profile key, etc. -- has changed. We
        /// want to post notifications for this update because various UI components
        /// may need to be updated. Note: It's possible that the avatar was also
        /// updated in this case.
        case something

        /// Something has changed, but we know it's only the avatar properties. We
        /// still want to post notifications to update the UI, but there are a few
        /// steps we can skip if it's only the avatar that's different.
        case avatarOnly

        /// "Nothing" changed, where "nothing" means "nothing important". There
        /// might still be updates to the profile, but they're internal-only and
        /// aren't reflected in the UI. For example, "lastMessagingDate" is used to
        /// decide when to fetch profiles, but it's not displayed to the user, so we
        /// can skip notifications if that's the only property that changed.
        case nothing
    }

    /// Applies `UserProfileChanges` to `self`.
    ///
    /// Returns a value indicating `changes`' user-visible impact.
    @discardableResult
    private func applyChanges(
        _ changes: UserProfileChanges,
        userProfileWriter: UserProfileWriter
    ) -> UserVisibleChange {
        let canModifyStorageServiceProperties: Bool
        switch internalAddress {
        case .localUser:
            canModifyStorageServiceProperties = {
                // Any properties stored in the storage service can only by modified by the
                // local user or the storage service. In particular, they should _not_ be
                // modified by profile fetches.
                switch userProfileWriter {
                case .debugging: fallthrough
                case .localUser: fallthrough
                case .messageBackupRestore: fallthrough
                case .registration: fallthrough
                case .storageService: fallthrough
                case .tests:
                    return true

                case .avatarDownload: fallthrough
                case .groupState: fallthrough
                case .linking: fallthrough
                case .metadataUpdate: fallthrough
                case .profileFetch: fallthrough
                case .reupload: fallthrough
                case .syncMessage:
                    return false

                case .changePhoneNumber: fallthrough
                case .systemContactsFetch: fallthrough
                case .unknown: fallthrough
                @unknown default:
                    owsFailDebug("Invalid userProfileWriter.")
                    return false
                }
            }()
        case .otherUser:
            canModifyStorageServiceProperties = true
        }

        func setIfChanged<T: Equatable>(_ newValue: OptionalChange<T>, keyPath: ReferenceWritableKeyPath<OWSUserProfile, T>) -> Int {
            switch newValue {
            case .setTo(let newValue) where newValue != self[keyPath: keyPath]:
                self[keyPath: keyPath] = newValue
                return 1
            case .setTo, .noChange:
                return 0
            }
        }

        // We special-case avatar changes in a few places.
        let canUpdateAvatarUrlPath = canModifyStorageServiceProperties || userProfileWriter == .reupload
        let canUpdateAvatarFileName = canUpdateAvatarUrlPath || userProfileWriter == .avatarDownload
        let didChangeAvatar = updateAvatar(
            avatarUrlPath: canUpdateAvatarUrlPath ? changes.avatarUrlPath : .noChange,
            avatarFileName: canUpdateAvatarFileName ? changes.avatarFileName : .noChange
        )

        // And we also care if user-visible properties change.
        var visibleChangeCount = 0
        if canModifyStorageServiceProperties {
            visibleChangeCount += setIfChanged(changes.givenName, keyPath: \.givenName)
            visibleChangeCount += setIfChanged(changes.familyName, keyPath: \.familyName)
        }
        visibleChangeCount += setIfChanged(changes.bio, keyPath: \.bio)
        visibleChangeCount += setIfChanged(changes.bioEmoji, keyPath: \.bioEmoji)
        visibleChangeCount += setIfChanged(changes.badges, keyPath: \.badges)
        visibleChangeCount += setIfChanged(changes.profileKey.map { $0 as Aes256Key? }, keyPath: \.profileKey)
        visibleChangeCount += setIfChanged(changes.isPhoneNumberShared, keyPath: \.isPhoneNumberShared)

        // Some properties are invisible/"polled", so changes don't matter.
        _ = setIfChanged(changes.lastFetchDate.map { $0 as Date? }, keyPath: \.lastFetchDate)
        _ = setIfChanged(changes.lastMessagingDate.map { $0 as Date? }, keyPath: \.lastMessagingDate)

        if visibleChangeCount > 0 {
            return .something
        }
        if didChangeAvatar {
            return .avatarOnly
        }
        return .nothing
    }

    /// Applies `UserProfileChanges` to `self` (& the db).
    ///
    /// If `self` hasn't been inserted, it will be inserted. Otherwise, a
    /// pattern similar to `anyUpdate` is followed where `self` and a copy from
    /// the database are both modified.
    ///
    /// This method has lots of side effects, such as:
    /// - Reconciling badges when fetching the local user's profile.
    /// - Inserting "profile update" chat events.
    /// - Re-indexing threads, group members, etc.
    /// - Updating storage service.
    /// - Posting notifications about profile updates & new profile keys.
    private func applyChanges(
        _ changes: UserProfileChanges,
        userProfileWriter: UserProfileWriter,
        tx: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        let displayNameBeforeLearningProfileName = displayNameBeforeLearningProfileNameIfNecessary(tx: tx.asV2Read)

        let internalAddress = self.internalAddress

        if case .otherUser(let address) = internalAddress {
            // We should never be writing to or updating the "local address" profile;
            // we should be using the "localProfilePhoneNumber" profile instead.
            owsAssertDebug(!address.isLocalAddress)
        }

        let oldInstance = Self.anyFetch(uniqueId: uniqueId, transaction: tx)
        oldInstance?.loadBadgeContent(tx: tx)
        let newInstance: OWSUserProfile

        // Always apply the changes to `self`.
        applyChanges(changes, userProfileWriter: userProfileWriter)

        let changeResult: UserVisibleChange
        if let oldInstance {
            newInstance = oldInstance.shallowCopy()
            changeResult = newInstance.applyChanges(changes, userProfileWriter: userProfileWriter)
            newInstance.anyOverwritingUpdate(transaction: tx)
        } else {
            newInstance = self
            changeResult = .something
            newInstance.anyInsert(transaction: tx)
        }

        loadBadgeContent(tx: tx)
        newInstance.loadBadgeContent(tx: tx)

        func changeSummary<T: Equatable>(for keyPath: KeyPath<OWSUserProfile, T?>, logDescription: StaticString) -> String? {
            let oldValue: T? = oldInstance?[keyPath: keyPath]
            let newValue: T? = newInstance[keyPath: keyPath]
            if newValue == oldValue {
                return nil
            }
            let oldValueDescription = oldValue != nil ? "something" : "nil"
            let newValueDescription = newValue != nil ? "something else" : "nil"
            return "\(logDescription) changed (\(oldValueDescription) -> \(newValueDescription))"
        }

        let changeSummaries: [String] = [
            changeSummary(for: \.profileKey, logDescription: "profileKey"),
            changeSummary(for: \.givenName, logDescription: "givenName"),
            changeSummary(for: \.familyName, logDescription: "familyName"),
            changeSummary(for: \.avatarUrlPath, logDescription: "avatarUrlPath"),
            changeSummary(for: \.avatarFileName, logDescription: "avatarFileName"),
        ].compacted()

        if !changeSummaries.isEmpty {
            Logger.info("Updated \(internalAddress): \(changeSummaries.joined(separator: ", "))")
        }

        if let completion {
            tx.addAsyncCompletionOffMain(completion)
        }

        if case .localUser = internalAddress {
            SSKEnvironment.shared.profileManagerRef.localProfileWasUpdated(self)
        }

        if case .localUser = internalAddress, case .setTo = changes.badges {
            DonationSubscriptionManager.reconcileBadgeStates(transaction: tx)
        }

        if let oldInstance {
            // Insert a profile change update in conversations, if necessary
            TSInfoMessage.insertProfileChangeMessagesIfNecessary(
                oldProfile: oldInstance,
                newProfile: newInstance,
                transaction: tx
            )
        }

        if
            let displayNameBeforeLearningProfileName,
            displayNameBeforeLearningProfileNameIfNecessary(tx: tx.asV2Read) == nil
        {
            /// We didn't have a pre-profile-key display name for this profile
            /// before applying changes, but we do know. Insert an info message
            /// to that effect.
            TSInfoMessage.insertLearnedProfileNameMessage(
                serviceId: displayNameBeforeLearningProfileName.serviceId,
                displayNameBefore: displayNameBeforeLearningProfileName.displayName,
                tx: tx.asV2Write
            )
        }

        updatePhoneNumberVisibilityIfNeeded(
            oldUserProfile: oldInstance,
            newUserProfile: newInstance,
            tx: tx.asV2Write
        )

        if changeResult == .nothing {
            return
        }

        // Profile changes, record updates with storage service. We don't store
        // avatar information on the service except for the local user.
        let shouldUpdateStorageService: Bool = {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard tsAccountManager.registrationState(tx: tx.asV2Read).isRegistered else {
                return false
            }
            guard userProfileWriter.shouldUpdateStorageService else {
                return false
            }
            switch internalAddress {
            case .localUser:
                // Never update local profile on storage service to reflect profile fetches.
                return userProfileWriter != .profileFetch
            case .otherUser:
                // Only update storage service if we changed something other than the avatar.
                return changeResult != .avatarOnly
            }
        }()

        if shouldUpdateStorageService {
            tx.addAsyncCompletionOffMain {
                switch internalAddress {
                case .localUser:
                    SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
                case .otherUser(let address):
                    SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: [address])
                }
            }
        }

        let oldProfileKey = oldInstance?.profileKey
        let newProfileKey = newInstance.profileKey

        tx.addAsyncCompletionOnMain {
            switch internalAddress {
            case .localUser:
                if oldProfileKey != newProfileKey {
                    NotificationCenter.default.postNotificationNameAsync(UserProfileNotifications.localProfileKeyDidChange, object: nil)
                }
                NotificationCenter.default.postNotificationNameAsync(UserProfileNotifications.localProfileDidChange, object: nil)
            case .otherUser(let address):
                NotificationCenter.default.postNotificationNameAsync(
                    UserProfileNotifications.otherUsersProfileDidChange,
                    object: nil,
                    userInfo: [UserProfileNotifications.profileAddressKey: address]
                )
            }
        }
    }

    private struct DisplayNameBeforeLearningProfileName {
        let serviceId: ServiceId
        let displayName: TSInfoMessage.DisplayNameBeforeLearningProfileName
    }

    /// Returns the display name for this profile if we have not yet learned the
    /// profile key.
    ///
    /// - Note
    /// This implementation deliberately avoids the typical `DisplayName`
    /// calculation in `ContactManager`. See comments inline.
    private func displayNameBeforeLearningProfileNameIfNecessary(
        tx: any DBReadTransaction
    ) -> DisplayNameBeforeLearningProfileName? {
        guard givenName == nil else {
            return nil
        }

        let signalServiceAddress: SignalServiceAddress
        switch internalAddress {
        case .localUser:
            return nil
        case .otherUser(let _address):
            signalServiceAddress = _address
        }

        let usernameLookupManager = DependenciesBridge.shared.usernameLookupManager
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable

        if
            let aci = signalServiceAddress.serviceId as? Aci,
            let username = usernameLookupManager.fetchUsername(forAci: aci, transaction: tx)
        {
            /// If we have their ACI and a username for that ACI, we'll prefer
            /// it by the same "prefer ACI identifiers" rule we use elsewhere,
            /// such as in thread merging.
            return DisplayNameBeforeLearningProfileName(
                serviceId: aci,
                displayName: .username(username)
            )
        } else if
            let serviceId = signalServiceAddress.serviceId,
            let recipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx),
            let phoneNumber = recipient.phoneNumber
        {
            /// We'll get here if this profile maps to one of your system
            /// contacts, and we'll ignore the system contact name here. That's
            /// also intentional, since we're interested in the display name
            /// exclusively in the Signal ecosystem (i.e., not including names
            /// the user brought with them, and that might change).
            return DisplayNameBeforeLearningProfileName(
                serviceId: serviceId,
                displayName: .phoneNumber(phoneNumber.stringValue)
            )
        }

        return nil
    }

    private func updatePhoneNumberVisibilityIfNeeded(
        oldUserProfile: OWSUserProfile?,
        newUserProfile: OWSUserProfile,
        tx: DBWriteTransaction
    ) {
        let shouldUpdateVisibility: Bool = {
            if (oldUserProfile?.givenName == nil) && (newUserProfile.givenName != nil) {
                return true
            }
            if newUserProfile.isPhoneNumberShared != oldUserProfile?.isPhoneNumberShared {
                return true
            }
            return false
        }()
        // Don't do anything unless the sharing setting was changed.
        guard shouldUpdateVisibility else {
            return
        }
        guard case .otherUser(let address) = internalAddress, let aci = address.aci else {
            return
        }
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let recipient = recipientDatabaseTable.fetchRecipient(serviceId: aci, transaction: tx)
        guard let recipient else {
            return
        }
        // Tell the cache to refresh its state for this recipient. It will check
        // whether or not the number should be visible based on this state and the
        // state of system contacts.
        SSKEnvironment.shared.signalServiceAddressCacheRef.updateRecipient(recipient, tx: tx)
    }

    /// Applies changes specified by the properties.
    public func update(
        givenName: OptionalChange<String?> = .noChange,
        familyName: OptionalChange<String?> = .noChange,
        bio: OptionalChange<String?> = .noChange,
        bioEmoji: OptionalChange<String?> = .noChange,
        avatarUrlPath: OptionalChange<String?> = .noChange,
        avatarFileName: OptionalChange<String?> = .noChange,
        lastFetchDate: OptionalChange<Date> = .noChange,
        lastMessagingDate: OptionalChange<Date> = .noChange,
        profileKey: OptionalChange<Aes256Key> = .noChange,
        badges: OptionalChange<[OWSUserProfileBadgeInfo]> = .noChange,
        isPhoneNumberShared: OptionalChange<Bool?> = .noChange,
        userProfileWriter: UserProfileWriter,
        transaction: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        applyChanges(
            UserProfileChanges(
                givenName: givenName,
                familyName: familyName,
                bio: bio,
                bioEmoji: bioEmoji,
                avatarUrlPath: avatarUrlPath,
                avatarFileName: avatarFileName,
                lastFetchDate: lastFetchDate,
                lastMessagingDate: lastMessagingDate,
                profileKey: profileKey,
                badges: badges,
                isPhoneNumberShared: isPhoneNumberShared
            ),
            userProfileWriter: userProfileWriter,
            tx: transaction,
            completion: completion
        )
    }

    #if USE_DEBUG_UI
    public func clearProfile(
        profileKey: Aes256Key,
        userProfileWriter: UserProfileWriter,
        transaction: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        // This is only used for debugging.
        owsAssertDebug(userProfileWriter == .debugging)
        update(
            givenName: .setTo(nil),
            familyName: .setTo(nil),
            bio: .setTo(nil),
            bioEmoji: .setTo(nil),
            avatarUrlPath: .setTo(nil),
            avatarFileName: .setTo(nil),
            profileKey: .setTo(profileKey),
            userProfileWriter: userProfileWriter,
            transaction: transaction,
            completion: completion
        )
    }
    #endif
}

// MARK: - Update without side effects

extension OWSUserProfile {
    /// Updates the given properties for this model on disk with no other
    /// side-effects, such as triggering profile fetches, updating storage
    /// service, or posting local notifications.
    ///
    /// - Important
    /// Only callers who are updating the profile in a vacuum, and are very sure
    /// they have the most up-to-date info about this profile, should call this.
    public func upsertWithNoSideEffects(
        givenName: String?,
        familyName: String?,
        avatarUrlPath: String?,
        profileKey: Aes256Key?,
        tx: SDSAnyWriteTransaction
    ) {
        self.givenName = givenName
        self.familyName = familyName
        self.avatarUrlPath = avatarUrlPath
        self.profileKey = profileKey

        anyUpsert(transaction: tx)
    }
}

// MARK: -

extension OWSUserProfile {
    static func getUserProfiles(for addresses: [Address], tx: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        return UserProfileFinder().userProfiles(for: addresses, tx: tx)
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(userProfileColumn column: OWSUserProfile.CodingKeys) {
        appendLiteral(OWSUserProfile.columnName(column))
    }
    mutating func appendInterpolation(userProfileColumnFullyQualified column: OWSUserProfile.CodingKeys) {
        appendLiteral(OWSUserProfile.columnName(column, fullyQualified: true))
    }
}
