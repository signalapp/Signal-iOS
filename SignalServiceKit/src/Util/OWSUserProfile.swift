//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Mantle

@objc
public class OWSUserProfileBadgeInfo: NSObject, SDSSwiftSerializable {
    @objc
    public let badgeId: String
    public var badge: ProfileBadge?    // nil until a call to `loadBadge()` or `fetchBadgeContent(transaction:)`

    // These properties are only valid for the current user
    public let expiration: UInt64?
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

@objc
public extension OWSUserProfile {

    static var maxNameLengthGlyphs: Int = 26
    // The max bytes for a user's profile name, encoded in UTF8.
    // Before encrypting and submitting we NULL pad the name data to this length.
    static var maxNameLengthBytes: Int = 128

    static let kMaxBioLengthGlyphs: Int = 140
    static let kMaxBioLengthBytes: Int = 512

    static let kMaxBioEmojiLengthGlyphs: Int = 1
    static let kMaxBioEmojiLengthBytes: Int = 32

    // MARK: - Bio

    @nonobjc
    private static let bioComponentCache = LRUCache<String, String>(maxSize: 256)
    private static let unfairLock = UnfairLock()

    var visibleBadges: [OWSUserProfileBadgeInfo] {
        let allBadges = profileBadgeInfo ?? []
        return allBadges.filter { $0.isVisible ?? true }
    }

    private static func filterBioComponentForDisplay(_ input: String?,
                                                     maxLengthGlyphs: Int,
                                                     maxLengthBytes: Int) -> String? {
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

    // Joins the two bio components into a single string
    // ready for display. It filters and enforces length
    // limits on the components.
    static func bioForDisplay(bio: String?, bioEmoji: String?) -> String? {
        var components = [String]()
        // TODO: We could use EmojiWithSkinTones to check for availability of the emoji.
        if let emoji = filterBioComponentForDisplay(bioEmoji,
                                                    maxLengthGlyphs: kMaxBioEmojiLengthGlyphs,
                                                    maxLengthBytes: kMaxBioEmojiLengthBytes) {
            components.append(emoji)
        }
        if let bioText = filterBioComponentForDisplay(bio,
                                                      maxLengthGlyphs: kMaxBioLengthGlyphs,
                                                      maxLengthBytes: kMaxBioLengthBytes) {
            components.append(bioText)
        }
        guard !components.isEmpty else {
            return nil
        }
        return components.joined(separator: " ")
    }

    // MARK: - Encryption

    class func encrypt(profileData: Data, profileKey: OWSAES256Key) -> Data? {
        return try? Aes256GcmEncryptedData.encrypt(profileData, key: profileKey.keyData).concatenate()
    }

    class func decrypt(profileData: Data, profileKey: OWSAES256Key) -> Data? {
        return try? Aes256GcmEncryptedData(concatenated: profileData).decrypt(key: profileKey.keyData)
    }

    class func decrypt(profileNameData: Data, profileKey: OWSAES256Key, address: SignalServiceAddress) -> PersonNameComponents? {
        guard let decryptedData = decrypt(profileData: profileNameData, profileKey: profileKey) else { return nil }

        // Unpad profile name. The given and family name are stored
        // in the string like "<given name><null><family name><null padding>"
        let nameSegments: [Data] = decryptedData.split(separator: 0x00)

        // Given name is required
        guard nameSegments.count > 0,
              let givenName = String(data: nameSegments[0], encoding: .utf8), !givenName.isEmpty else {
            Logger.warn("unexpectedly missing first name for \(address), isLocal: \(address.isLocalAddress).")
            return nil
        }

        // Family name is optional
        let familyName: String?
        if nameSegments.count > 1 {
            familyName = String(data: nameSegments[1], encoding: .utf8)
        } else {
            familyName = nil
        }

        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        nameComponents.familyName = familyName
        return nameComponents
    }

    class func decrypt(profileStringData: Data, profileKey: OWSAES256Key) -> String? {
        guard let decryptedData = decrypt(profileData: profileStringData, profileKey: profileKey) else {
            return nil
        }

        // Remove padding.
        let segments: [Data] = decryptedData.split(separator: 0x00)
        guard let firstSegment = segments.first else {
            return nil
        }
        guard let string = String(data: firstSegment, encoding: .utf8), !string.isEmpty else {
            return nil
        }
        return string
    }

    class func encrypt(profileNameComponents: PersonNameComponents, profileKey: OWSAES256Key) -> ProfileValue? {
        let givenName: String? = profileNameComponents.givenName?.trimToGlyphCount(maxNameLengthGlyphs)
        guard var paddedNameData = givenName?.data(using: .utf8) else { return nil }
        if let familyName = profileNameComponents.familyName?.trimToGlyphCount(maxNameLengthGlyphs) {
            // Insert a null separator
            paddedNameData.count += 1
            guard let familyNameData = familyName.data(using: .utf8) else { return nil }
            paddedNameData.append(familyNameData)
        }

        // The Base 64 lengths reflect encryption + Base 64 encoding
        // of the max-length padded value.
        //
        // Two names plus null separator.
        let totalNameMaxLength = Int(maxNameLengthBytes) * 2 + 1
        let paddedLengths: [Int]
        let validBase64Lengths: [Int]
        owsAssertDebug(totalNameMaxLength == 257)
        paddedLengths = [53, 257 ]
        validBase64Lengths = [108, 380 ]

        // All encrypted profile names should be the same length on the server,
        // so we pad out the length with null bytes to the maximum length.
        return encrypt(data: paddedNameData,
                       profileKey: profileKey,
                       paddedLengths: paddedLengths,
                       validBase64Lengths: validBase64Lengths)
    }

    class func encrypt(data unpaddedData: Data,
                       profileKey: OWSAES256Key,
                       paddedLengths: [Int],
                       validBase64Lengths: [Int]) -> ProfileValue? {

        guard paddedLengths == paddedLengths.sorted() else {
            owsFailDebug("paddedLengths have incorrect ordering.")
            return nil
        }

        guard let paddedData = ({ () -> Data? in
            guard let paddedLength = paddedLengths.first(where: { $0 >= unpaddedData.count }) else {
                owsFailDebug("Oversize value: \(unpaddedData.count) > \(paddedLengths)")
                return nil
            }

            var paddedData = unpaddedData
            let paddingByteCount = paddedLength - paddedData.count
            paddedData.count += paddingByteCount

            assert(paddedData.count == paddedLength)
            return paddedData
        }()) else {
            owsFailDebug("Could not pad value.")
            return nil
        }

        guard let encrypted = encrypt(profileData: paddedData, profileKey: profileKey) else {
            owsFailDebug("Could not encrypt.")
            return nil
        }
        let value = ProfileValue(encrypted: encrypted, validBase64Lengths: validBase64Lengths)
        guard value.hasValidBase64Length else {
            owsFailDebug("Value has invalid base64 length: \(encrypted.count) -> \(value.encryptedBase64.count) not in \(validBase64Lengths).")
            return nil
        }
        return value
    }

    // MARK: - Indexing

    /// Reindex associated models.
    ///
    /// The profile can affect how accounts, recipients, contact threads, and
    /// group threads are indexed, so we need to re-index them whenever the
    /// profile changes.
    func reindexAssociatedModels(transaction: SDSAnyWriteTransaction) {
        if let signalAccount = AnySignalAccountFinder().signalAccount(for: address, transaction: transaction) {
            FullTextSearchFinder.modelWasUpdated(model: signalAccount, transaction: transaction)
        }

        if let signalRecipient = AnySignalRecipientFinder().signalRecipient(for: address, transaction: transaction) {
            FullTextSearchFinder.modelWasUpdated(model: signalRecipient, transaction: transaction)
        }

        if let contactThread = TSContactThread.getWithContactAddress(address, transaction: transaction) {
            FullTextSearchFinder.modelWasUpdated(model: contactThread, transaction: transaction)
        }

        TSGroupMember.enumerateGroupMembers(for: address, transaction: transaction) { groupMember, _ in
            FullTextSearchFinder.modelWasUpdated(model: groupMember, transaction: transaction)
        }
    }
}

// MARK: -

@objc
public class ProfileValue: NSObject {
    public let encrypted: Data

    let validBase64Lengths: [Int]

    required init(encrypted: Data,
                  validBase64Lengths: [Int]) {
        self.encrypted = encrypted
        self.validBase64Lengths = validBase64Lengths
    }

    @objc
    var encryptedBase64: String {
        encrypted.base64EncodedString()
    }

    @objc
    var hasValidBase64Length: Bool {
        validBase64Lengths.contains(encryptedBase64.count)
    }
}

// MARK: -

@objc
public class UserProfileChanges: NSObject {
    @objc
    public class OptionalStringValue: NSObject {
        @objc
        public let value: String?

        init(_ value: String?) {
            self.value = value
        }
    }
    @objc
    public class BoolValue: NSObject {
        @objc
        public let value: Bool

        init(_ value: Bool) {
            self.value = value
        }
    }
    @objc
    public class DateValue: NSObject {
        @objc
        public let value: Date

        init(_ value: Date) {
            self.value = value
        }
    }
    @objc
    public class OptionalProfileKeyValue: NSObject {
        @objc
        public let value: OWSAES256Key?

        init(_ value: OWSAES256Key?) {
            self.value = value
        }
    }

    @objc
    public var givenName: OptionalStringValue?
    @objc
    public var familyName: OptionalStringValue?
    @objc
    public var bio: OptionalStringValue?
    @objc
    public var bioEmoji: OptionalStringValue?
    @objc
    public var avatarUrlPath: OptionalStringValue?
    @objc
    public var avatarFileName: OptionalStringValue?
    @objc
    public var lastFetchDate: DateValue?
    @objc
    public var lastMessagingDate: DateValue?
    @objc
    public var profileKey: OptionalProfileKeyValue?
    @objc
    public var badges: [OWSUserProfileBadgeInfo]?

    @objc
    public var isStoriesCapable: BoolValue?
    @objc
    public var canReceiveGiftBadges: BoolValue?
    @objc
    public var isPniCapable: BoolValue?

    @objc
    public let updateMethodName: String

    init(file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        // We format the filename & line number in a format compatible
        // with XCode's "Open Quickly..." feature.
        self.updateMethodName = "[\(filename):\(line) \(function)]"
    }
}

// MARK: - Update With... Methods

@objc
public extension OWSUserProfile {

    @objc(updateWithGivenName:familyName:userProfileWriter:authedAccount:transaction:completion:)
    func update(
        givenName: String?,
        familyName: String?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: OWSUserProfileCompletion?
    ) {
        let changes = UserProfileChanges()
        changes.givenName = .init(givenName)
        changes.familyName = .init(familyName)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    func update(
        givenName: String?,
        familyName: String?,
        avatarUrlPath: String?,
        avatarFileName: String?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: OWSUserProfileCompletion?
    ) {
        let changes = UserProfileChanges()
        changes.givenName = .init(givenName)
        changes.familyName = .init(familyName)
        changes.avatarUrlPath = .init(avatarUrlPath)
        changes.avatarFileName = .init(avatarFileName)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @objc(updateWithGivenName:familyName:bio:bioEmoji:badges:avatarUrlPath:lastFetchDate:isStoriesCapable:canReceiveGiftBadges:isPniCapable:userProfileWriter:authedAccount:transaction:completion:)
    func update(
        givenName: String?,
        familyName: String?,
        bio: String?,
        bioEmoji: String?,
        badges: [OWSUserProfileBadgeInfo],
        avatarUrlPath: String?,
        lastFetchDate: Date,
        isStoriesCapable: Bool,
        canReceiveGiftBadges: Bool,
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: OWSUserProfileCompletion?
    ) {
        let changes = UserProfileChanges()
        changes.givenName = .init(givenName)
        changes.familyName = .init(familyName)
        changes.bio = .init(bio)
        changes.bioEmoji = .init(bioEmoji)
        changes.badges = badges
        changes.avatarUrlPath = .init(avatarUrlPath)
        changes.lastFetchDate = .init(lastFetchDate)

        changes.isStoriesCapable = .init(isStoriesCapable)
        changes.canReceiveGiftBadges = .init(canReceiveGiftBadges)
        changes.isPniCapable = .init(isPniCapable)

        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @objc(updateWithGivenName:familyName:bio:bioEmoji:badges:avatarUrlPath:avatarFileName:lastFetchDate:isStoriesCapable:canReceiveGiftBadges:isPniCapable:userProfileWriter:authedAccount:transaction:completion:)
    func update(
        givenName: String?,
        familyName: String?,
        bio: String?,
        bioEmoji: String?,
        badges: [OWSUserProfileBadgeInfo],
        avatarUrlPath: String?,
        avatarFileName: String?,
        lastFetchDate: Date,
        isStoriesCapable: Bool,
        canReceiveGiftBadges: Bool,
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: OWSUserProfileCompletion?
    ) {
        let changes = UserProfileChanges()
        changes.givenName = .init(givenName)
        changes.familyName = .init(familyName)
        changes.bio = .init(bio)
        changes.bioEmoji = .init(bioEmoji)
        changes.badges = badges
        changes.avatarUrlPath = .init(avatarUrlPath)
        changes.avatarFileName = .init(avatarFileName)
        changes.lastFetchDate = .init(lastFetchDate)

        changes.isStoriesCapable = .init(isStoriesCapable)
        changes.canReceiveGiftBadges = .init(canReceiveGiftBadges)
        changes.isPniCapable = .init(isPniCapable)

        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    func update(
        avatarFileName: String?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        let changes = UserProfileChanges()
        changes.avatarFileName = .init(avatarFileName)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }

    func clear(
        profileKey: OWSAES256Key?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: OWSUserProfileCompletion?
    ) {
        // This is only used for debugging.
        owsAssertDebug(userProfileWriter == .debugging)
        let changes = UserProfileChanges()
        changes.profileKey = .init(profileKey)
        changes.givenName = .init(nil)
        changes.familyName = .init(nil)
        changes.bio = .init(nil)
        changes.bioEmoji = .init(nil)
        // builder.isStoriesCapable = .init(nil)
        changes.avatarUrlPath = .init(nil)
        changes.avatarFileName = .init(nil)
        // builder.lastFetchDate = .init(nil)
        // builder.lastMessagingDate = .init(nil)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    func update(
        profileKey: OWSAES256Key?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: OWSUserProfileCompletion?
    ) {
        let changes = UserProfileChanges()
        changes.profileKey = .init(profileKey)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    @objc(updateWithGivenName:familyName:avatarUrlPath:userProfileWriter:authedAccount:transaction:completion:)
    func update(
        givenName: String?,
        familyName: String?,
        avatarUrlPath: String?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction,
        completion: OWSUserProfileCompletion?
    ) {
        let changes = UserProfileChanges()
        changes.givenName = .init(givenName)
        changes.familyName = .init(familyName)
        changes.avatarUrlPath = .init(avatarUrlPath)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

    func update(
        isStoriesCapable: Bool,
        canReceiveGiftBadges: Bool,
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        let changes = UserProfileChanges()
        changes.isStoriesCapable = .init(isStoriesCapable)
        changes.canReceiveGiftBadges = .init(canReceiveGiftBadges)
        changes.isPniCapable = .init(isPniCapable)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }

    func update(
        lastFetchDate: Date,
        isStoriesCapable: Bool,
        canReceiveGiftBadges: Bool,
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        let changes = UserProfileChanges()
        changes.lastFetchDate = .init(lastFetchDate)

        changes.isStoriesCapable = .init(isStoriesCapable)
        changes.canReceiveGiftBadges = .init(canReceiveGiftBadges)
        changes.isPniCapable = .init(isPniCapable)

        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }

    func update(
        lastMessagingDate: Date,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        let changes = UserProfileChanges()
        changes.lastMessagingDate = .init(lastMessagingDate)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }

    #if TESTABLE_BUILD
    func update(
        lastFetchDate: Date,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        let changes = UserProfileChanges()
        changes.lastFetchDate = .init(lastFetchDate)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }

    func discardProfileKey(
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        let changes = UserProfileChanges()
        changes.profileKey = .init(nil)
        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }
    #endif
}

extension OWSUserProfile {
    static func getFor(keys: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        let resolvedAddresses = keys.map { address -> SignalServiceAddress in
            owsAssertDebug(address.isValid)
            return resolve(address)
        }
        return userProfileFinder.userProfiles(for: resolvedAddresses, transaction: transaction)
    }
}
