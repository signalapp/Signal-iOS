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

extension OWSUserProfile {
    public var serviceId: ServiceId? { recipientUUID.flatMap { try? ServiceId.parseFrom(serviceIdString: $0) } }
}

@objc
public extension OWSUserProfile {

    static var maxNameLengthGlyphs: Int = 26
    // The max bytes for a user's profile name, encoded in UTF8.
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

    class func encrypt(profileData: Data, profileKey: OWSAES256Key) throws -> Data {
        return try Aes256GcmEncryptedData.encrypt(profileData, key: profileKey.keyData).concatenate()
    }

    class func decrypt(profileData: Data, profileKey: OWSAES256Key) -> Data? {
        return try? Aes256GcmEncryptedData(concatenated: profileData).decrypt(key: profileKey.keyData)
    }

    class func decrypt(profileNameData: Data, profileKey: OWSAES256Key) -> PersonNameComponents? {
        guard let decryptedData = decrypt(profileData: profileNameData, profileKey: profileKey) else { return nil }

        func parseNameSegment(_ nameSegment: Data?) -> String? {
            return nameSegment.flatMap({ String(data: $0, encoding: .utf8) })?.strippedOrNil
        }

        // Unpad profile name. The given and family name are stored
        // in the string like "<given name><null><family name><null padding>"
        let nameSegments: [Data] = decryptedData.split(separator: 0x00)

        // Given name is required
        guard let givenName = parseNameSegment(nameSegments.first) else {
            Logger.warn("unexpectedly missing given name")
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
        let segments: [Data] = decryptedData.split(separator: 0x00)
        guard let firstSegment = segments.first else {
            return nil
        }
        guard let string = String(data: firstSegment, encoding: .utf8), !string.isEmpty else {
            return nil
        }
        return string
    }

    @nonobjc
    class func encrypt(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        profileKey: OWSAES256Key
    ) throws -> ProfileValue {
        let encodedValues: [Data] = [givenName.dataValue, familyName?.dataValue].compacted()
        let encodedValue = Data(encodedValues.joined(separator: Data([0])))

        // Two names plus null separator.
        let totalNameMaxLength = Int(maxNameLengthBytes) * 2 + 1
        let paddedLengths: [Int]
        owsAssertDebug(totalNameMaxLength == 257)
        paddedLengths = [53, 257]

        return try encrypt(data: encodedValue, profileKey: profileKey, paddedLengths: paddedLengths)
    }

    @nonobjc
    class func encrypt(data unpaddedData: Data, profileKey: OWSAES256Key, paddedLengths: [Int]) throws -> ProfileValue {
        guard paddedLengths == paddedLengths.sorted() else {
            throw OWSAssertionError("paddedLengths have incorrect ordering.")
        }

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
    func reindexAssociatedModels(transaction tx: SDSAnyWriteTransaction) {
        if let signalAccount = SignalAccountFinder().signalAccount(for: address, tx: tx) {
            FullTextSearchFinder.modelWasUpdated(model: signalAccount, transaction: tx)
        }

        if let signalRecipient = SignalRecipientFinder().signalRecipient(for: address, tx: tx) {
            FullTextSearchFinder.modelWasUpdated(model: signalRecipient, transaction: tx)
        }

        if let contactThread = TSContactThread.getWithContactAddress(address, transaction: tx) {
            FullTextSearchFinder.modelWasUpdated(model: contactThread, transaction: tx)
        }

        TSGroupMember.enumerateGroupMembers(for: address, transaction: tx) { groupMember, _ in
            FullTextSearchFinder.modelWasUpdated(model: groupMember, transaction: tx)
        }
    }

    // MARK: - Fetching & Creating

    @objc(getOrBuildUserProfileForAddress:authedAccount:transaction:)
    class func getOrBuildUserProfile(
        for address: SignalServiceAddress,
        authedAccount: AuthedAccount,
        transaction tx: SDSAnyWriteTransaction
    ) -> OWSUserProfile {
        let address = resolve(address.withNormalizedPhoneNumber())
        owsAssertDebug(address.isValid)

        // If we already have a profile for this address, return it.
        if let userProfile = fetchNormalizeAndPruneUserProfiles(normalizedAddress: address, tx: tx) {
            return userProfile
        }

        // Otherwise, create & return a new profile for this address.
        let userProfile = OWSUserProfile(address: address)
        if address.phoneNumber == kLocalProfileInvariantPhoneNumber {
            userProfile.update(
                profileKey: OWSAES256Key.generateRandom(),
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
        let userProfiles = userProfileFinder.fetchUserProfiles(matchingAnyComponentOf: normalizedAddress, tx: tx)

        var matchingProfiles = [OWSUserProfile]()
        for userProfile in userProfiles {
            let matchesAddress: Bool = {
                if let userProfileServiceIdString = userProfile.recipientUUID {
                    // If the UserProfile has a ServiceId, then so must normalizedAddress.
                    return userProfileServiceIdString == normalizedAddress.serviceIdUppercaseString
                } else if let userProfilePhoneNumber = userProfile.recipientPhoneNumber {
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
                owsAssertDebug(userProfile.recipientUUID != nil)
                owsAssertDebug(userProfile.recipientPhoneNumber != nil)
                owsAssertDebug(userProfile.recipientPhoneNumber == normalizedAddress.phoneNumber)
                userProfile.recipientPhoneNumber = nil
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
        if userProfile.recipientUUID != newServiceIdString {
            userProfile.recipientUUID = newServiceIdString
            didUpdate = true
        }
        let newPhoneNumber = newAddress.phoneNumber
        if userProfile.recipientPhoneNumber != newPhoneNumber {
            userProfile.recipientPhoneNumber = newPhoneNumber
            didUpdate = true
        }
        if didUpdate {
            userProfile.anyOverwritingUpdate(transaction: tx)
        }
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
                .trimToGlyphCount(OWSUserProfile.maxNameLengthGlyphs)
                .trimToUtf8ByteCount(OWSUserProfile.maxNameLengthBytes)
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
        bio: String?,
        bioEmoji: String?,
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
        changes.bio = .init(bio)
        changes.bioEmoji = .init(bioEmoji)
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
        changes.isPniCapable = .init(isPniCapable)

        apply(
            changes,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: completion
        )
    }

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
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        let changes = UserProfileChanges()
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
        isPniCapable: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        let changes = UserProfileChanges()
        changes.lastFetchDate = .init(lastFetchDate)
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
        return userProfileFinder.userProfiles(for: resolvedAddresses, tx: transaction)
    }
}
