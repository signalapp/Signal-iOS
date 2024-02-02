//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

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
        badge = profileManager.badgeStore.fetchBadgeWithId(badgeId, readTx: transaction)
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

    // MARK: - Constants

    public enum Constants {
        // For these values, "glyphs" represent what the user should be able to
        // type in an ideal world (eg "your name can contain 26 characters").
        // "Bytes" represents what the server enforces. Note that it's possible to
        // run into either limit (eg 5 emoji might hit the byte limit and 26 ASCII
        // characters might hit the glyph limit).

        fileprivate static let maxNameLengthGlyphs: Int = 26
        fileprivate static let maxNameLengthBytes: Int = 128

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
    /// All other users are represented by their real ACI/PNI/E164 addresses.
    @objc
    public var internalAddress: SignalServiceAddress {
        SignalServiceAddress(serviceIdString: serviceIdString, phoneNumber: phoneNumber)
    }

    /// The "public" address.
    ///
    /// All users are represented by their real ACI/PNI/E164 addresses.
    @objc
    public var publicAddress: SignalServiceAddress {
        Self.publicAddress(for: internalAddress)
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
    private(set) public var profileKey: OWSAES256Key?

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

    @objc
    private(set) public var isPniCapable: Bool

    public convenience init(address: NormalizedDatabaseRecordAddress?) {
        owsAssertDebug(address != nil)
        self.init(
            id: nil,
            uniqueId: UUID().uuidString,
            serviceIdString: address?.serviceId?.serviceIdUppercaseString,
            phoneNumber: address?.phoneNumber,
            avatarFileName: nil,
            avatarUrlPath: nil,
            profileKey: nil,
            givenName: nil,
            familyName: nil,
            bio: nil,
            bioEmoji: nil,
            badges: [],
            lastFetchDate: nil,
            lastMessagingDate: nil,
            isPniCapable: false
        )
    }

    init(
        id: RowId?,
        uniqueId: String,
        serviceIdString: String?,
        phoneNumber: String?,
        avatarFileName: String?,
        avatarUrlPath: String?,
        profileKey: OWSAES256Key?,
        givenName: String?,
        familyName: String?,
        bio: String?,
        bioEmoji: String?,
        badges: [OWSUserProfileBadgeInfo],
        lastFetchDate: Date?,
        lastMessagingDate: Date?,
        isPniCapable: Bool
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
        self.isPniCapable = isPniCapable
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
            isPniCapable: isPniCapable
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
        guard isPniCapable == otherProfile.isPniCapable else { return false }
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
        try container.encodeIfPresent(LegacySDSSerializer().serializeAsLegacySDSData(property: profileKey), forKey: .profileKey)
        try container.encodeIfPresent(givenName, forKey: .givenName)
        try container.encodeIfPresent(familyName, forKey: .familyName)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(bioEmoji, forKey: .bioEmoji)
        try container.encode(JSONEncoder().encode(badges), forKey: .badges)
        try container.encodeIfPresent(lastFetchDate, forKey: .lastFetchDate)
        try container.encodeIfPresent(lastMessagingDate, forKey: .lastMessagingDate)
        try container.encode(true, forKey: .isStoriesCapable)
        try container.encode(true, forKey: .canReceiveGiftBadges)
        try container.encode(isPniCapable, forKey: .isPniCapable)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(UInt.self, forKey: .recordType)
        guard decodedRecordType == Self.recordType else {
            owsFailDebug("Unexpected record type: \(decodedRecordType)")
            throw SDSError.invalidValue
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
        isPniCapable = try container.decode(Bool.self, forKey: .isPniCapable)
    }

    private static func decodeProfileKey(_ profileKeyData: Data) throws -> OWSAES256Key {
        guard profileKeyData.count == kAES256_KeyByteLength, let profileKey = OWSAES256Key(data: profileKeyData) else {
            // Historically, we encoded this using an NSKeyedArchiver. We assume it's
            // encoded in this way if it's not exactly 32 bytes.
            return try LegacySDSSerializer().deserializeLegacySDSData(profileKeyData, propertyName: "profileKey")
        }
        return profileKey
    }

    // MARK: - Profile Addresses

    @objc
    public static let localProfileAddress = SignalServiceAddress(phoneNumber: Constants.localProfilePhoneNumber)

    @objc
    public static func isLocalProfileAddress(_ address: SignalServiceAddress) -> Bool {
        return address.phoneNumber == Constants.localProfilePhoneNumber || address.isLocalAddress
    }

    /// Converts an "internal" or "public" address to an "internal" one.
    @objc
    public static func internalAddress(for publicAddress: SignalServiceAddress) -> SignalServiceAddress {
        return isLocalProfileAddress(publicAddress) ? localProfileAddress : publicAddress
    }

    /// Converts an "internal" or "public" address to a "public" one.
    private static func publicAddress(for internalAddress: SignalServiceAddress) -> SignalServiceAddress {
        if isLocalProfileAddress(internalAddress) {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            if let localAddress = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress {
                return localAddress
            } else {
                owsFailDebug("Missing localAddress.")
                // fallthrough
            }
        }
        return internalAddress
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
            DispatchQueue.global().async { OWSFileSystem.deleteFileIfExists(oldAvatarFilePath) }
        }

        self.avatarUrlPath = newAvatarUrlPath
        self.avatarFileName = newAvatarFileName
        return true
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

    @objc
    public static func profileAvatarFilePath(for filename: String) -> String {
        owsAssertDebug(!filename.isEmpty)
        return Self.profileAvatarsDirPath.appendingPathComponent(filename)
    }

    // TODO: We may want to clean up this directory in the "orphan cleanup" logic.

    public static func resetProfileStorage() {
        AssertIsOnMainThread()
        do {
            try FileManager.default.removeItem(atPath: profileAvatarsDirPath)
        } catch {
            Logger.error("Failed to delete database: \(error)")
        }
    }

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

    public class func encrypt(profileData: Data, profileKey: OWSAES256Key) throws -> Data {
        return try Aes256GcmEncryptedData.encrypt(profileData, key: profileKey.keyData).concatenate()
    }

    public class func decrypt(profileData: Data, profileKey: OWSAES256Key) -> Data? {
        return try? Aes256GcmEncryptedData(concatenated: profileData).decrypt(key: profileKey.keyData)
    }

    class func decrypt(profileNameData: Data, profileKey: OWSAES256Key) -> PersonNameComponents? {
        guard let decryptedData = decrypt(profileData: profileNameData, profileKey: profileKey) else {
            return nil
        }

        func parseNameSegment(_ nameSegment: Data?) -> String? {
            return nameSegment.flatMap({ String(data: $0, encoding: .utf8) })?.strippedOrNil
        }

        // Unpad profile name. The given and family name are stored in the string
        // like "<given name><null><family name><null padding>"
        let nameSegments: [Data] = decryptedData.split(separator: 0x00, maxSplits: 2)

        guard let givenName = parseNameSegment(nameSegments.first) else {
            return nil
        }

        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        // Family name is optional
        nameComponents.familyName = parseNameSegment(nameSegments.dropFirst().first)
        return nameComponents
    }

    class func decrypt(profileStringData: Data, profileKey: OWSAES256Key) -> String? {
        guard let decryptedData = decrypt(profileData: profileStringData, profileKey: profileKey) else {
            return nil
        }

        // Remove padding.
        let segments: [Data] = decryptedData.split(separator: 0x00, maxSplits: 1)
        guard let firstSegment = segments.first else {
            return nil
        }
        guard let string = String(data: firstSegment, encoding: .utf8), !string.isEmpty else {
            return nil
        }
        return string
    }

    class func decrypt(profileBooleanData: Data, profileKey: OWSAES256Key) -> Bool? {
        switch decrypt(profileData: profileBooleanData, profileKey: profileKey) {
        case Data([1]):
            return true
        case Data([0]):
            return false
        default:
            return nil
        }
    }

    public class func encrypt(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        profileKey: OWSAES256Key
    ) throws -> ProfileValue {
        let encodedValues: [Data] = [givenName.dataValue, familyName?.dataValue].compacted()
        let encodedValue = Data(encodedValues.joined(separator: Data([0])))
        assert(Constants.maxNameLengthBytes * 2 + 1 == 257)
        return try encrypt(data: encodedValue, profileKey: profileKey, paddedLengths: [53, 257])
    }

    public class func encrypt(data unpaddedData: Data, profileKey: OWSAES256Key, paddedLengths: [Int]) throws -> ProfileValue {
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

    // MARK: - Indexing

    /// Reindex associated models.
    ///
    /// The profile can affect how accounts, recipients, contact threads, and
    /// group threads are indexed, so we need to re-index them whenever the
    /// profile changes.
    private func reindexAssociatedModels(transaction tx: SDSAnyWriteTransaction) {
        if let signalAccount = SignalAccountFinder().signalAccount(for: internalAddress, tx: tx) {
            FullTextSearchFinder.modelWasUpdated(model: signalAccount, transaction: tx)
        }

        if let signalRecipient = SignalRecipientFinder().signalRecipient(for: internalAddress, tx: tx) {
            FullTextSearchFinder.modelWasUpdated(model: signalRecipient, transaction: tx)
        }

        if let contactThread = TSContactThread.getWithContactAddress(internalAddress, transaction: tx) {
            FullTextSearchFinder.modelWasUpdated(model: contactThread, transaction: tx)
        }

        TSGroupMember.enumerateGroupMembers(for: internalAddress, transaction: tx) { groupMember, _ in
            FullTextSearchFinder.modelWasUpdated(model: groupMember, transaction: tx)
        }
    }

    // MARK: - Fetching & Creating

    @objc
    public static func getUserProfile(for address: SignalServiceAddress, transaction tx: SDSAnyReadTransaction) -> OWSUserProfile? {
        let address = internalAddress(for: address)
        owsAssertDebug(address.isValid)
        return UserProfileFinder().userProfile(for: address, transaction: tx)
    }

    @objc
    public static func doesLocalProfileExist(transaction tx: SDSAnyReadTransaction) -> Bool {
        return UserProfileFinder().userProfile(for: localProfileAddress, transaction: tx) != nil
    }

    @objc(getOrBuildUserProfileForAddress:authedAccount:transaction:)
    public class func getOrBuildUserProfile(
        for address: SignalServiceAddress,
        authedAccount: AuthedAccount,
        transaction tx: SDSAnyWriteTransaction
    ) -> OWSUserProfile {
        let address = internalAddress(for: address.withNormalizedPhoneNumber())
        owsAssertDebug(address.isValid)

        // If we already have a profile for this address, return it.
        if let userProfile = fetchNormalizeAndPruneUserProfiles(normalizedAddress: address, tx: tx) {
            return userProfile
        }

        // Otherwise, create & return a new profile for this address.
        let userProfile = OWSUserProfile(
            address: NormalizedDatabaseRecordAddress(address: address)
        )
        if address.phoneNumber == Constants.localProfilePhoneNumber {
            userProfile.update(
                profileKey: .setTo(OWSAES256Key.generateRandom()),
                userProfileWriter: .localUser,
                authedAccount: authedAccount,
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
    private class func fetchNormalizeAndPruneUserProfiles(
        normalizedAddress: SignalServiceAddress,
        tx: SDSAnyWriteTransaction
    ) -> OWSUserProfile? {
        let userProfiles = UserProfileFinder().fetchUserProfiles(matchingAnyComponentOf: normalizedAddress, tx: tx)

        var matchingProfiles = [OWSUserProfile]()
        for userProfile in userProfiles {
            let matchesAddress: Bool = {
                if let userProfileServiceIdString = userProfile.serviceIdString {
                    // If the UserProfile has a ServiceId, then so must normalizedAddress.
                    return userProfileServiceIdString == normalizedAddress.serviceIdUppercaseString
                } else if let userProfilePhoneNumber = userProfile.phoneNumber {
                    // If the UserProfile doesn't have a ServiceId, then it can match just the phone number.
                    return userProfilePhoneNumber == normalizedAddress.phoneNumber
                }
                return false
            }()

            if matchesAddress {
                matchingProfiles.append(userProfile)
            } else {
                // Non-matching profiles must have some other `ServiceId` and a matching
                // phone number. This is outdated information that we should update.
                owsAssertDebug(userProfile.serviceIdString != nil)
                owsAssertDebug(userProfile.phoneNumber != nil)
                owsAssertDebug(userProfile.phoneNumber == normalizedAddress.phoneNumber)
                userProfile.phoneNumber = nil
                userProfile.anyOverwritingUpdate(transaction: tx)
            }
        }
        // Get rid of any duplicates -- these shouldn't exist.
        for redundantProfile in matchingProfiles.dropFirst() {
            redundantProfile.anyRemove(transaction: tx)
        }
        if let chosenProfile = matchingProfiles.first {
            updateAddressIfNeeded(userProfile: chosenProfile, newAddress: normalizedAddress, tx: tx)
            return chosenProfile
        }
        return nil
    }

    private class func updateAddressIfNeeded(
        userProfile: OWSUserProfile,
        newAddress: SignalServiceAddress,
        tx: SDSAnyWriteTransaction
    ) {
        var didUpdate = false
        let newServiceIdString = newAddress.serviceIdUppercaseString
        if userProfile.serviceIdString != newServiceIdString {
            userProfile.serviceIdString = newServiceIdString
            didUpdate = true
        }
        let newPhoneNumber = newAddress.phoneNumber
        if userProfile.phoneNumber != newPhoneNumber {
            userProfile.phoneNumber = newPhoneNumber
            didUpdate = true
        }
        if didUpdate {
            userProfile.anyOverwritingUpdate(transaction: tx)
        }
    }

    // MARK: - Database Hooks

    public func anyDidInsert(transaction: SDSAnyWriteTransaction) {
        reindexAssociatedModels(transaction: transaction)
        modelReadCaches.userProfileReadCache.didInsertOrUpdate(userProfile: self, transaction: transaction)
    }

    public func anyDidUpdate(transaction: SDSAnyWriteTransaction) {
        modelReadCaches.userProfileReadCache.didInsertOrUpdate(userProfile: self, transaction: transaction)
    }

    public func anyDidRemove(transaction: SDSAnyWriteTransaction) {
        modelReadCaches.userProfileReadCache.didRemove(userProfile: self, transaction: transaction)
    }

    public func anyDidFetchOne(transaction: SDSAnyReadTransaction) {
        modelReadCaches.userProfileReadCache.didReadUserProfile(self, transaction: transaction)
    }

    public func anyDidEnumerateOne(transaction: SDSAnyReadTransaction) {
        modelReadCaches.userProfileReadCache.didReadUserProfile(self, transaction: transaction)
    }

    // MARK: - ObjC Compability

    @objc
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

        public static func parse(truncating: String) -> (Self, didTruncate: Bool)? {
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
    var profileKey: OptionalChange<OWSAES256Key>
    var badges: OptionalChange<[OWSUserProfileBadgeInfo]>
    var isPniCapable: OptionalChange<Bool>
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
        let isLocalUserProfile = Self.isLocalProfileAddress(internalAddress)
        let canModifyStorageServiceProperties = !isLocalUserProfile || {
            // Any properties stored in the storage service can only by modified by the
            // local user or the storage service. In particular, they should _not_ be
            // modified by profile fetches.
            switch userProfileWriter {
            case .debugging: fallthrough
            case .localUser: fallthrough
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
        visibleChangeCount += setIfChanged(changes.profileKey.map { $0 as OWSAES256Key? }, keyPath: \.profileKey)

        // Some properties are invisible/"polled", so changes don't matter.
        _ = setIfChanged(changes.lastFetchDate.map { $0 as Date? }, keyPath: \.lastFetchDate)
        _ = setIfChanged(changes.lastMessagingDate.map { $0 as Date? }, keyPath: \.lastMessagingDate)
        _ = setIfChanged(changes.isPniCapable, keyPath: \.isPniCapable)

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
        authedAccount: AuthedAccount,
        tx: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        let isLocalUserProfile = Self.isLocalProfileAddress(internalAddress)
        if isLocalUserProfile {
            // We should never be writing to or updating the "local address" profile;
            // we should be using the "localProfilePhoneNumber" profile instead.
            owsAssertDebug(internalAddress.phoneNumber == Constants.localProfilePhoneNumber)
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

        if isLocalUserProfile {
            profileManager.localProfileWasUpdated(self)
            subscriptionManager.reconcileBadgeStates(transaction: tx)
        }

        if let oldInstance {
            // Note: We always re-index just-inserted models elsewhere.
            let profileNameMatches = (
                oldInstance.givenName == newInstance.givenName
                && oldInstance.familyName == newInstance.familyName
            )
            if !profileNameMatches {
                reindexAssociatedModels(transaction: tx)
            }

            // Insert a profile change update in conversations, if necessary
            TSInfoMessage.insertProfileChangeMessagesIfNecessary(
                oldProfile: oldInstance,
                newProfile: newInstance,
                transaction: tx
            )
        }

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
            if isLocalUserProfile {
                // Never update local profile on storage service to reflect profile fetches.
                return userProfileWriter != .profileFetch
            } else {
                // Only update storage service if we changed something other than the avatar.
                return changeResult != .avatarOnly
            }
        }()

        if shouldUpdateStorageService {
            tx.addAsyncCompletionOffMain {
                if isLocalUserProfile {
                    self.storageServiceManager.recordPendingLocalAccountUpdates()
                } else {
                    self.storageServiceManager.recordPendingUpdates(updatedAddresses: [ self.internalAddress ])
                }
            }
        }

        let oldProfileKey = oldInstance?.profileKey
        let newProfileKey = newInstance.profileKey

        tx.addAsyncCompletionOnMain { [internalAddress] in
            if isLocalUserProfile {
                if oldProfileKey != newProfileKey {
                    NotificationCenter.default.postNotificationNameAsync(UserProfileNotifications.localProfileKeyDidChange, object: nil)
                }
                NotificationCenter.default.postNotificationNameAsync(UserProfileNotifications.localProfileDidChange, object: nil)
            } else {
                NotificationCenter.default.postNotificationNameAsync(
                    UserProfileNotifications.otherUsersProfileDidChange,
                    object: nil,
                    userInfo: [UserProfileNotifications.profileAddressKey: internalAddress]
                )
            }
        }
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
        profileKey: OptionalChange<OWSAES256Key> = .noChange,
        badges: OptionalChange<[OWSUserProfileBadgeInfo]> = .noChange,
        isPniCapable: OptionalChange<Bool> = .noChange,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
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
                isPniCapable: isPniCapable
            ),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            tx: transaction,
            completion: completion
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc(updateWithGivenName:familyName:userProfileWriter:authedAccount:transaction:completion:)
    func update(
        givenName: String?,
        familyName: String?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        update(
            givenName: .setTo(givenName),
            familyName: .setTo(familyName),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc(updateWithGivenName:familyName:bio:bioEmoji:badges:avatarUrlPath:lastFetchDate:isPniCapable:userProfileWriter:authedAccount:transaction:completion:)
    func update(
        givenName: String?,
        familyName: String?,
        bio: String?,
        bioEmoji: String?,
        badges: [OWSUserProfileBadgeInfo],
        avatarUrlPath: String?,
        lastFetchDate: Date,
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        update(
            givenName: .setTo(givenName),
            familyName: .setTo(familyName),
            bio: .setTo(bio),
            bioEmoji: .setTo(bioEmoji),
            avatarUrlPath: .setTo(avatarUrlPath),
            lastFetchDate: .setTo(lastFetchDate),
            badges: .setTo(badges),
            isPniCapable: .setTo(isPniCapable),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc(updateWithGivenName:familyName:bio:bioEmoji:badges:avatarUrlPath:avatarFileName:lastFetchDate:isPniCapable:userProfileWriter:authedAccount:transaction:completion:)
    func update(
        givenName: String?,
        familyName: String?,
        bio: String?,
        bioEmoji: String?,
        badges: [OWSUserProfileBadgeInfo],
        avatarUrlPath: String?,
        avatarFileName: String?,
        lastFetchDate: Date,
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        update(
            givenName: .setTo(givenName),
            familyName: .setTo(familyName),
            bio: .setTo(bio),
            bioEmoji: .setTo(bioEmoji),
            avatarUrlPath: .setTo(avatarUrlPath),
            avatarFileName: .setTo(avatarFileName),
            lastFetchDate: .setTo(lastFetchDate),
            badges: .setTo(badges),
            isPniCapable: .setTo(isPniCapable),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc
    public func update(
        avatarFileName: String?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        update(
            avatarFileName: .setTo(avatarFileName),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc
    public func clearProfile(
        profileKey: OWSAES256Key,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
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
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc
    public func update(
        profileKey: OWSAES256Key,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        update(
            profileKey: .setTo(profileKey),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc(updateWithGivenName:familyName:avatarUrlPath:userProfileWriter:authedAccount:transaction:completion:)
    func update(
        givenName: String?,
        familyName: String?,
        avatarUrlPath: String?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: (() -> Void)?
    ) {
        update(
            givenName: .setTo(givenName),
            familyName: .setTo(familyName),
            avatarUrlPath: .setTo(avatarUrlPath),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc
    public func update(
        lastFetchDate: Date,
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        update(
            lastFetchDate: .setTo(lastFetchDate),
            isPniCapable: .setTo(isPniCapable),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }

    @available(swift, obsoleted: 1.0)
    @objc
    public func update(
        lastMessagingDate: Date,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        update(
            lastMessagingDate: .setTo(lastMessagingDate),
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }
}

extension OWSUserProfile {
    static func getFor(keys: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        let internalAddresses = keys.map { address -> SignalServiceAddress in
            owsAssertDebug(address.isValid)
            return internalAddress(for: address)
        }
        return UserProfileFinder().userProfiles(for: internalAddresses, tx: transaction)
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
