//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// This class has been ported over from objc and the notes attached to that are reproduced below.
/// Note that the veracity of the thread safety claims seems dubious.
///
/// This class can be safely accessed and used from any thread.
///
/// Access to most state should happen while locked. Writes should happen off the main thread, wherever possible.
public class OWSProfileManager: NSObject, ProfileManagerProtocol {
    public static let maxAvatarDiameterPixels: UInt = 1024
    public static let notificationKeyUserProfileWriter = "kNSNotificationKey_UserProfileWriter"

    private let whitelistedPhoneNumbersStore = KeyValueStore(collection: "kOWSProfileManager_UserWhitelistCollection")
    private let whitelistedServiceIdsStore = KeyValueStore(collection: "kOWSProfileManager_UserUUIDWhitelistCollection")
    private let whitelistedGroupsStore = KeyValueStore(collection: "kOWSProfileManager_GroupWhitelistCollection")
    private let settingsStore = KeyValueStore(collection: "kOWSProfileManager_SettingsStore")

    private let pendingUpdateRequests = AtomicValue<[OWSProfileManager.ProfileUpdateRequest]>([], lock: .init())

    /// This property is used by the Swift extension to ensure that only one
    /// profile update is in flight at a time. It should only be accessed on the
    /// main thread.
    private var isUpdatingProfileOnService: Bool = false

    // The old objc code used synchronized a lock which is a recursive lock so using NSRecursiveLock here to recreate that behavior.
    private let lock = NSRecursiveLock()

    // This may not need to be @Atomic, but it was in the old code. Most of the time it's accessed while holding lock, but sometimes
    // it is not. The pattern of use in the objc code has been replicated here for the time being.
    @Atomic private var _localUserProfile: OWSUserProfile?

    private let metadataStore = KeyValueStore(collection: "kOWSProfileManager_Metadata")
    @Atomic private var isRotatingProfileKey: Bool = false

    private let appReadiness: AppReadiness
    public let badgeStore = BadgeStore()

    init(appReadiness: AppReadiness, databaseStorage: SDSDatabaseStorage) {
        AssertIsOnMainThread()

        self.appReadiness = appReadiness

        super.init()

        SwiftSingletons.register(self)

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.rotateLocalProfileKeyIfNecessary()
            self.updateProfileOnServiceIfNecessary(authedAccount: .implicit())
            Self.updateStorageServiceIfNecessary()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)), name: .OWSApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(_:)), name: SSKReachability.owsReachabilityDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(blockListDidChange(_:)), name: BlockingManager.blockListDidChange, object: nil)
    }

    // MARK: - User Profile Accessor

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        // Clear out so we re-initialize if we ever re-run the "on launch" logic,
        // such as after a completed database transfer.
        lock.withLock {
            _localUserProfile = nil
        }

        // Since localUserProfile can create a transaction, we want to make sure it's not called for the first
        // time unexpectedly (e.g. in a nested transaction.)
        _ = localUserProfile
    }

    // MARK: - Local Profile

    public func localProfileWasUpdated(_ localUserProfile: OWSUserProfile) {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)
        lock.withLock {
            _localUserProfile = localUserProfile.shallowCopy()
        }
    }

    /// This computed var should only be accessed from the main thread.
    public var localProfileKey: Aes256Key {
        owsAssertDebug(self.localUserProfile.profileKey?.keyData.count ?? 0 == Aes256Key.keyByteLength)

        // FIXME: The objc code ignored the nullability match here; for now we've forced it with `!` but this is unsatisfactory.
        return self.localUserProfile.profileKey!
    }
    /// localUserProfileExists is true if there is _ANY_ local profile.
    /// This method should only be called from the main thread.
    public func localProfileExists(with transaction: SDSAnyReadTransaction) -> Bool {
        OWSUserProfile.doesLocalProfileExist(transaction: transaction)
    }

    /// hasLocalProfile is true if there is a local profile with a name or avatar.
    public var hasLocalProfile: Bool {
        hasProfileName || localProfileAvatarImage != nil
    }

    public var hasProfileName: Bool {
        !localGivenName.isEmptyOrNil
    }

    public var localGivenName: String? {
        localUserProfile.filteredGivenName
    }

    public var localFamilyName: String? {
        localUserProfile.filteredFamilyName
    }

    public var localFullName: String? {
        localUserProfile.filteredFullName
    }

    public var localProfileAvatarImage: UIImage? {
        guard let avatarFileName = localUserProfile.avatarFileName else {
            return nil
        }
        return loadProfileAvatar(filename: avatarFileName)
    }

    public var localProfileAvatarData: Data? {
        guard let filename = localUserProfile.avatarFileName, !filename.isEmpty else {
            return nil
        }
        return loadProfileAvatarData(filename: filename)
    }

    public var localProfileBadgeInfo: [OWSUserProfileBadgeInfo]? {
        localUserProfile.badges
    }

    @objc(localProfileSnapshotWithShouldIncludeAvatar:)
    public func localProfileSnapshot(shouldIncludeAvatar: Bool) -> OWSProfileSnapshot {
        profileSnapshot(for: localUserProfile, shouldIncludeAvatar: shouldIncludeAvatar)
    }

    private func profileSnapshot(for userProfile: OWSUserProfile, shouldIncludeAvatar: Bool) -> OWSProfileSnapshot {
        var avatarData: Data?
        if shouldIncludeAvatar, let avatarFilename = userProfile.avatarFileName, !avatarFilename.isEmpty {
            avatarData = loadProfileAvatarData(filename: avatarFilename)
        }
        return OWSProfileSnapshot(givenName: userProfile.filteredGivenName,
                                  familyName: userProfile.filteredFamilyName,
                                  fullName: userProfile.filteredFullName,
                                  bio: userProfile.bio,
                                  bioEmoji: userProfile.bioEmoji,
                                  avatarData: avatarData,
                                  profileBadgeInfo: userProfile.badges)
    }

    public static func avatarData(avatarImage image: UIImage) -> Data? {
        var image = image
        let maxAvatarBytes = 5_000_000

        if image.pixelWidth != maxAvatarDiameterPixels || image.pixelHeight != maxAvatarDiameterPixels {
            // To help ensure the user is being shown the same cropping of their avatar as
            // everyone else will see, we want to be sure that the image was resized before this point.
            owsFailDebug("Avatar image should have been resized before trying to upload")
            image = image.resizedImage(toFillPixelSize: .init(width: CGFloat(maxAvatarDiameterPixels), height: CGFloat(maxAvatarDiameterPixels)))
        }

        guard let data = image.jpegData(compressionQuality: 0.95) else {
            return nil
        }
        if data.count > maxAvatarBytes {
            // Our avatar dimensions are so small that it's incredibly unlikely we wouldn't be able to fit our profile
            // photo. e.g. generating pure noise at our resolution compresses to ~200k.
            owsFailDebug("Surprised to find profile avatar was too large. Was it scaled properly? image: \(image)")
        }

        return data
    }

    private var localUserProfileShallowCopy: OWSUserProfile? {
        lock.withLock {
            if let _localUserProfile {
                owsAssertDebug(_localUserProfile.profileKey != nil)
                return _localUserProfile.shallowCopy()
            } else {
                return nil
            }
        }
    }

    // comments in objc implied this should only be used internally within this file, but making
    // this fileprivate revealed the comments were inaccurate
    var localUserProfile: OWSUserProfile {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)
        if let localUserProfileShallowCopy {
            return localUserProfileShallowCopy
        }

        // copied from objc; thread-safety claims are ?
        //
        // We create the profile outside the lock critical section to avoid any risk
        // of deadlock. Thanks to ensureLocalProfileCached, there should be no risk
        // of races. And races should be harmless since: a)
        // getOrBuildUserProfileForInternalAddress is idempotent and b) we use the
        // "update with..." pattern.
        //
        // We first try using a read block to avoid opening a write block.
        if let localUserProfile = SSKEnvironment.shared.databaseStorageRef.read(block: {getLocalUserProfile($0)}) {
            return localUserProfile.shallowCopy()
        }
        let localUserProfile = SSKEnvironment.shared.databaseStorageRef.write { transaction in
            let localUserProfile = OWSUserProfile.getOrBuildUserProfileForLocalUser(userProfileWriter: .localUser, tx: transaction)
            owsAssertDebug(localUserProfile.profileKey != nil)
            return localUserProfile
        }
        return lock.withLock {
            _localUserProfile = localUserProfile
            return localUserProfile.shallowCopy()
        }
    }

    fileprivate func getLocalUserProfile(_ tx: SDSAnyReadTransaction) -> OWSUserProfile? {
        // This appears to be kludged in here by the objc code. It's unclear why this variable
        // has the effect it has in this function. Likely this sort of thing should not be getting
        // called at all if migrations are not already completed, but I guess we don't have a
        // process wide guarantee of that?
        let migrationsAreComplete = GRDBSchemaMigrator.areMigrationsComplete

        if migrationsAreComplete, let localUserProfileShallowCopy {
            return localUserProfileShallowCopy
        }

        let localUserProfile = OWSUserProfile.getUserProfileForLocalUser(tx: tx)

        if migrationsAreComplete {
            return lock.withLock {
                _localUserProfile = localUserProfile
                return localUserProfile?.shallowCopy()
            }
        }

        return localUserProfile?.shallowCopy()
    }

    // MARK: - Profile Whitelist

    #if USE_DEBUG_UI

    public func clearProfileWhitelist() {
        Logger.warn("Clearing the profile whitelist.")

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            self.whitelistedPhoneNumbersStore.removeAll(transaction: transaction.asV2Write)
            self.whitelistedServiceIdsStore.removeAll(transaction: transaction.asV2Write)
            self.whitelistedGroupsStore.removeAll(transaction: transaction.asV2Write)

            owsAssertDebug(self.whitelistedPhoneNumbersStore.numberOfKeys(transaction: transaction.asV2Read) == 0)
            owsAssertDebug(self.whitelistedServiceIdsStore.numberOfKeys(transaction: transaction.asV2Read) == 0)
            owsAssertDebug(self.whitelistedGroupsStore.numberOfKeys(transaction: transaction.asV2Read) == 0)
        }
    }

    public func debug_regenerateLocalProfileWithSneakyTransaction() {
        let userProfile = localUserProfile
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            userProfile.clearProfile(profileKey: Aes256Key(), userProfileWriter: .debugging, transaction: transaction, completion: nil)
        }
        Task {
            do {
                try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
            } catch {
                Logger.error("Error: \(error)")
            }
        }
    }

    #endif

    public func setLocalProfileKey(_ key: Aes256Key, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        let localUserProfile = lock.withLock {
            // If it didn't exist, create it in a safe way as accessing the property
            // will do a sneaky transaction.
            if let _localUserProfile {
                return _localUserProfile
            }

            // We assert on the ivar directly here, as we want this to be cached already
            // by the time this method is called. If it's not, we've changed our caching
            // logic and should re-evaluate this method.
            owsFailDebug("Missing local profile when setting key.")
            let localUserProfile = OWSUserProfile.getOrBuildUserProfileForLocalUser(userProfileWriter: .localUser, tx: transaction)
            _localUserProfile = localUserProfile
            return localUserProfile
        }

        localUserProfile.update(profileKey: .setTo(key), userProfileWriter: userProfileWriter, transaction: transaction, completion: nil)
    }

    public func normalizeRecipientInProfileWhitelist(_ recipient: SignalRecipient, tx: SDSAnyWriteTransaction) {
        swift_normalizeRecipientInProfileWhitelist(recipient, tx: tx)
    }

    public func addUser(toProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(address.isValid)
        addUsers(toProfileWhitelist: [address], userProfileWriter: userProfileWriter, transaction: transaction)
    }

    public func addUsers(toProfileWhitelist addresses: [SignalServiceAddress], userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        let addressesToAdd = addressesNotBlockedOrInWhitelist(addresses, transaction: transaction)
        addConfirmedUnwhitelistedAddresses(addressesToAdd, userProfileWriter: userProfileWriter, transaction: transaction)
    }

    public func removeUser(fromProfileWhitelist address: SignalServiceAddress) {
        owsAssertDebug(address.isValid)

        removeUsers(fromProfileWhitelist: [address])
    }

    public func removeUser(fromProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(address.isValid)

        let addressesToRemove = addressesInWhitelist([address], transaction: transaction)
        removeConfirmedWhitelistedAddresses(addressesToRemove, userProfileWriter: userProfileWriter, transaction: transaction)
    }

    // TODO: We could add a userProfileWriter parameter.
    private func removeUsers(fromProfileWhitelist addresses: [SignalServiceAddress]) {
        // Try to avoid opening a write transaction.
        SSKEnvironment.shared.databaseStorageRef.asyncRead { readTransaction in
            let addressesToRemove = self.addressesInWhitelist(addresses, transaction: readTransaction)
            if addressesToRemove.isEmpty {
                return
            }
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { writeTransaction in
                self.removeConfirmedWhitelistedAddresses(addressesToRemove, userProfileWriter: .localUser, transaction: writeTransaction)
            }
        }
    }

    private func addressesNotBlockedOrInWhitelist(_ addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> Set<SignalServiceAddress> {
        var notBlockedOrInWhitelist = Set<SignalServiceAddress>()
        for address in addresses {
            // If the address is blocked, we don't want to include it
            if SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(address, transaction: transaction) || RecipientHidingManagerObjcBridge.isHiddenAddress(address, tx: transaction) {
                continue
            }

            if !isAddressInWhitelist(address, tx: transaction) {
                notBlockedOrInWhitelist.insert(address)
            }
        }

        return notBlockedOrInWhitelist
    }

    private func addressesInWhitelist(_ addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> Set<SignalServiceAddress> {
        var whitelistedAddresses = Set<SignalServiceAddress>()

        for address in addresses {
            if isAddressInWhitelist(address, tx: transaction) {
                whitelistedAddresses.insert(address)
            }
        }

        return whitelistedAddresses
    }

    private func isAddressInWhitelist(_ address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> Bool {
        if let uppercaseServiceId = address.serviceIdUppercaseString, whitelistedServiceIdsStore.hasValue(uppercaseServiceId, transaction: tx.asV2Read) {
            return true
        }

        if let phoneNumber = address.phoneNumber, whitelistedPhoneNumbersStore.hasValue(phoneNumber, transaction: tx.asV2Read) {
            return true
        }

        return false
    }

    private func removeConfirmedWhitelistedAddresses(_ addressesToRemove: Set<SignalServiceAddress>, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        guard !addressesToRemove.isEmpty else {
            return
        }

        for address in addressesToRemove {
            // Historically we put both the ACI and phone number into their respective
            // stores. We currently save only the best identifier, but we should still
            // try and remove both to handle these historical cases.
            if let uppercaseServiceId = address.serviceIdUppercaseString {
                whitelistedServiceIdsStore.removeValue(forKey: uppercaseServiceId, transaction: transaction.asV2Write)
            }
            if let phoneNumber = address.phoneNumber {
                whitelistedPhoneNumbersStore.removeValue(forKey: phoneNumber, transaction: transaction.asV2Write)
            }

            if let thread = TSContactThread.getWithContactAddress(address, transaction: transaction) {
                SSKEnvironment.shared.databaseStorageRef.touch(thread: thread, shouldReindex: false, transaction: transaction)
            }
        }

        transaction.addSyncCompletion {
            // Mark the removed whitelisted addresses for update
            if OWSUserProfile.shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter) {
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: Array(addressesToRemove))
            }

            for address in addressesToRemove {
                NotificationCenter.default.postNotificationNameAsync(UserProfileNotifications.profileWhitelistDidChange, object: nil, userInfo: [
                    UserProfileNotifications.profileAddressKey: address,
                    Self.notificationKeyUserProfileWriter: NSNumber(value: userProfileWriter.rawValue),
                ])
            }
        }
    }

    private func addConfirmedUnwhitelistedAddresses(_ addressesToAdd: Set<SignalServiceAddress>, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        guard !addressesToAdd.isEmpty else {
            return
        }

        for address in addressesToAdd {
            let serviceId = address.serviceId
            if let serviceId = serviceId as? Aci {
                whitelistedServiceIdsStore.setBool(true, key: serviceId.serviceIdUppercaseString, transaction: transaction.asV2Write)
            } else if let phoneNumber = address.phoneNumber {
                whitelistedPhoneNumbersStore.setBool(true, key: phoneNumber, transaction: transaction.asV2Write)
            } else if let serviceId = serviceId as? Pni {
                whitelistedServiceIdsStore.setBool(true, key: serviceId.serviceIdUppercaseString, transaction: transaction.asV2Write)
            }

            if let thread = TSContactThread.getWithContactAddress(address, transaction: transaction) {
                SSKEnvironment.shared.databaseStorageRef.touch(thread: thread, shouldReindex: false, transaction: transaction)
            }
        }

        transaction.addSyncCompletion {
            // Mark the new whitelisted addresses for update
            if OWSUserProfile.shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter) {
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: Array(addressesToAdd))
            }

            for address in addressesToAdd {
                NotificationCenter.default.postNotificationNameAsync(UserProfileNotifications.profileWhitelistDidChange, object: nil, userInfo: [
                    UserProfileNotifications.profileAddressKey: address,
                    Self.notificationKeyUserProfileWriter: NSNumber(value: userProfileWriter.rawValue),
                ])
            }
        }
    }

    public func isUser(inProfileWhitelist address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        owsAssertDebug(address.isValid)

        if SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(address, transaction: transaction) || RecipientHidingManagerObjcBridge.isHiddenAddress(address, tx: transaction) {
            return false
        }

        return isAddressInWhitelist(address, tx: transaction)
    }

    public func addGroupId(toProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!groupId.isEmpty)
        let groupIdKey = groupKey(groupId: groupId)
        if !whitelistedGroupsStore.hasValue(groupIdKey, transaction: transaction.asV2Read) {
            addConfirmedUnwhitelistedGroupId(groupId, userProfileWriter: userProfileWriter, transaction: transaction)
        }
    }

    public func removeGroupId(fromProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!groupId.isEmpty)
        let groupIdKey = groupKey(groupId: groupId)
        if whitelistedGroupsStore.hasValue(groupIdKey, transaction: transaction.asV2Read) {
            removeConfirmedWhitelistedGroupId(groupId, userProfileWriter: userProfileWriter, transaction: transaction)
        }
    }

    private func removeConfirmedWhitelistedGroupId(_ groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!groupId.isEmpty)
        let groupIdKey = groupKey(groupId: groupId)
        whitelistedGroupsStore.removeValue(forKey: groupIdKey, transaction: transaction.asV2Write)
        groupIdWhitelistWasUpdated(groupId, userProfileWriter: userProfileWriter, transaction: transaction)
    }

    private func addConfirmedUnwhitelistedGroupId(_ groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!groupId.isEmpty)
        let groupIdKey = groupKey(groupId: groupId)
        whitelistedGroupsStore.setBool(true, key: groupIdKey, transaction: transaction.asV2Write)
        groupIdWhitelistWasUpdated(groupId, userProfileWriter: userProfileWriter, transaction: transaction)
    }

    private func groupIdWhitelistWasUpdated(_ groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            SSKEnvironment.shared.databaseStorageRef.touch(thread: groupThread, shouldReindex: false, transaction: transaction)
        }

        transaction.addSyncCompletion {
            // Mark the group for update
            if OWSUserProfile.shouldUpdateStorageServiceForUserProfileWriter(userProfileWriter) {
                self.recordPendingUpdatesForStorageService(groupId: groupId)
            }

            NotificationCenter.default.postNotificationNameAsync(UserProfileNotifications.profileWhitelistDidChange, object: nil, userInfo: [
                UserProfileNotifications.profileGroupIdKey: groupId,
                Self.notificationKeyUserProfileWriter: NSNumber(value: userProfileWriter.rawValue)
            ])
        }
    }

    private func recordPendingUpdatesForStorageService(groupId: Data) {
        owsAssertDebug(!groupId.isEmpty)
        SSKEnvironment.shared.databaseStorageRef.asyncRead { transaction in
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                owsFailDebug("Missing groupThread.")
                return
            }
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(groupModel: groupThread.groupModel)
        }
    }

    public func addThread(toProfileWhitelist thread: TSThread, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        if thread.isGroupThread, let groupThread = thread as? TSGroupThread {
            addGroupId(toProfileWhitelist: groupThread.groupModel.groupId, userProfileWriter: userProfileWriter, transaction: transaction)
        } else if !thread.isGroupThread, let contactThread = thread as? TSContactThread {
            addUser(toProfileWhitelist: contactThread.contactAddress, userProfileWriter: userProfileWriter, transaction: transaction)
        }
    }

    public func isGroupId(inProfileWhitelist groupId: Data, transaction: SDSAnyReadTransaction) -> Bool {
        owsAssertDebug(!groupId.isEmpty)
        if SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(groupId, transaction: transaction) {
            return false
        }
        let groupIdKey = groupKey(groupId: groupId)
        return whitelistedGroupsStore.hasValue(groupIdKey, transaction: transaction.asV2Read)
    }

    public func isThread(inProfileWhitelist thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        if thread.isGroupThread, let groupThread = thread as? TSGroupThread {
            return isGroupId(inProfileWhitelist: groupThread.groupModel.groupId, transaction: transaction)
        } else if !thread.isGroupThread, let contactThread = thread as? TSContactThread {
            return isUser(inProfileWhitelist: contactThread.contactAddress, transaction: transaction)
        } else {
            return false
        }
    }

    // MARK: Other User's Profiles

    public func profileKeyData(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Data? {
        profileKey(for: address, transaction: transaction)?.keyData
    }

    public func profileKey(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Aes256Key? {
        owsAssertDebug(address.isValid)
        let userProfile = getUserProfile(for: address, transaction: transaction)
        return userProfile?.profileKey
    }

    public func unfilteredGivenName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(address.isValid)
        return getUserProfile(for: address, transaction: transaction)?.givenName
    }

    public func givenName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(address.isValid)
        return getUserProfile(for: address, transaction: transaction)?.filteredGivenName
    }

    public func unfilteredFamilyName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(address.isValid)
        return getUserProfile(for: address, transaction: transaction)?.familyName
    }

    public func familyName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(address.isValid)
        return getUserProfile(for: address, transaction: transaction)?.filteredFamilyName
    }

    public func fullName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(address.isValid)
        return getUserProfile(for: address, transaction: transaction)?.filteredFullName
    }

    public func profileAvatar(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> UIImage? {
        owsAssertDebug(address.isValid)
        let userProfile = getUserProfile(for: address, transaction: transaction)
        guard let avatarFileName = userProfile?.avatarFileName, !avatarFileName.isEmpty else {
            return nil
        }
        return loadProfileAvatar(filename: avatarFileName)
    }

    public func hasProfileAvatarData(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        let userProfile = getUserProfile(for: address, transaction: transaction)
        guard let avatarFileName = userProfile?.avatarFileName, !avatarFileName.isEmpty else {
            return false
        }
        let filePath = OWSUserProfile.profileAvatarFilePath(for: avatarFileName)
        return OWSFileSystem.fileOrFolderExists(atPath: filePath)
    }

    public func profileAvatarData(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Data? {
        owsAssertDebug(address.isValid)
        let userProfile = getUserProfile(for: address, transaction: transaction)
        guard let avatarFileName = userProfile?.avatarFileName, !avatarFileName.isEmpty else {
            return nil
        }
        return loadProfileAvatarData(filename: avatarFileName)
    }

    public func profileAvatarURLPath(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(address.isValid)
        let userProfile = getUserProfile(for: address, transaction: transaction)
        return userProfile?.avatarUrlPath
    }

    public func profileBioForDisplay(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(address.isValid)
        let userProfile = getUserProfile(for: address, transaction: transaction)
        return OWSUserProfile.bioForDisplay(bio: userProfile?.bio, bioEmoji: userProfile?.bioEmoji)
    }

    public func getUserProfile(for addressParam: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        _getUserProfile(for: addressParam, tx: transaction)
    }

    // MARK: - Avatar Disk Cache

    private func loadProfileAvatarData(filename: String) -> Data? {
        owsAssertDebug(!filename.isEmpty)

        let filePath = OWSUserProfile.profileAvatarFilePath(for: filename)
        let avatarData = try? NSData(contentsOfFile: filePath) as Data

        guard let avatarData, avatarData.ows_isValidImage else {
            Logger.warn("Failed to get valid avatar data")
            return nil
        }
        return avatarData
    }

    private func loadProfileAvatar(filename: String) -> UIImage? {
        guard !filename.isEmpty else {
            return nil
        }

        guard let data = loadProfileAvatarData(filename: filename) else {
            return nil
        }

        guard let image = UIImage(data: data) else {
            Logger.warn("Could not load profile avatar.")
            return nil
        }
        return image
    }

    public func rotateProfileKeyUponRecipientHide(withTx tx: SDSAnyWriteTransaction) {
        rotateProfileKeyUponRecipientHideObjC(tx: tx)
    }

    // MARK: - Notifications

    @objc
    private func applicationDidBecomeActive(_ notification: NSNotification) {
        AssertIsOnMainThread()
        // TODO: Sync if necessary.
        updateProfileOnServiceIfNecessary(authedAccount: .implicit())
    }

    @objc
    private func reachabilityChanged(_ notification: NSNotification) {
        AssertIsOnMainThread()
        updateProfileOnServiceIfNecessary(authedAccount: .implicit())
    }

    @objc
    private func blockListDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.rotateLocalProfileKeyIfNecessary()
        }
    }

    // MARK: - Clean Up

    public static func allProfileAvatarFilePaths(transaction: SDSAnyReadTransaction) -> Set<String> {
        OWSUserProfile.allProfileAvatarFilePaths(tx: transaction)
    }

    // MARK: - Profile Key Rotation

    public func forceRotateLocalProfileKeyForGroupDeparture(with transaction: SDSAnyWriteTransaction) {
        forceRotateLocalProfileKeyForGroupDepartureObjc(tx: transaction)
    }

    public func groupKey(groupId: Data) -> String {
        groupId.hexadecimalString
    }
}

extension OWSProfileManager: ProfileManager {
    public func fetchLocalUsersProfile(authedAccount: AuthedAccount) -> Promise<FetchedProfile> {
        return Promise.wrapAsync {
            let profileFetcher = SSKEnvironment.shared.profileFetcherRef
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            return try await profileFetcher.fetchProfile(
                for: tsAccountManager.localIdentifiersWithMaybeSneakyTransaction(authedAccount: authedAccount).aci,
                authedAccount: authedAccount
            )
        }
    }

    public func updateProfile(
        address: OWSUserProfile.InsertableAddress,
        decryptedProfile: DecryptedProfile?,
        avatarUrlPath: OptionalChange<String?>,
        avatarFileName: OptionalChange<String?>,
        profileBadges: [OWSUserProfileBadgeInfo],
        lastFetchDate: Date,
        userProfileWriter: UserProfileWriter,
        tx: SDSAnyWriteTransaction
    ) {
        AssertNotOnMainThread()

        let userProfile = OWSUserProfile.getOrBuildUserProfile(
            for: address,
            userProfileWriter: userProfileWriter,
            tx: tx
        )

        var givenNameChange: OptionalChange<String> = .noChange
        var familyNameChange: OptionalChange<String?> = .noChange
        var bioChange: OptionalChange<String?> = .noChange
        var bioEmojiChange: OptionalChange<String?> = .noChange
        var isPhoneNumberSharedChange: OptionalChange<Bool?> = .noChange
        if let decryptedProfile {
            do {
                if let nameComponents = try decryptedProfile.nameComponents.get() {
                    givenNameChange = .setTo(nameComponents.givenName)
                    familyNameChange = .setTo(nameComponents.familyName)
                }
            } catch {
                Logger.warn("Couldn't decrypt profile name: \(error)")
            }
            do {
                if let bio = try decryptedProfile.bio.get() {
                    bioChange = .setTo(bio)
                }
            } catch {
                Logger.warn("Couldn't decrypt profile bio: \(error)")
            }
            do {
                if let bioEmoji = try decryptedProfile.bioEmoji.get() {
                    bioEmojiChange = .setTo(bioEmoji)
                }
            } catch {
                Logger.warn("Couldn't decrypt profile bio emoji: \(error)")
            }
            do {
                if let phoneNumberSharing = try decryptedProfile.phoneNumberSharing.get() {
                    isPhoneNumberSharedChange = .setTo(phoneNumberSharing)
                }
            } catch {
                Logger.warn("Couldn't decrypt phone number sharing: \(error)")
            }
        }

        userProfile.update(
            givenName: givenNameChange.map({ $0 as String? }),
            familyName: familyNameChange,
            bio: bioChange,
            bioEmoji: bioEmojiChange,
            avatarUrlPath: avatarUrlPath,
            avatarFileName: avatarFileName,
            lastFetchDate: .setTo(lastFetchDate),
            badges: .setTo(profileBadges),
            isPhoneNumberShared: isPhoneNumberSharedChange,
            userProfileWriter: userProfileWriter,
            transaction: tx,
            completion: nil
        )
    }

    // The main entry point for updating the local profile. It will:
    //
    // * Enqueue a service update.
    // * Attempt that service update.
    //
    // The returned promise will fail if the service can't be updated
    // (or in the unlikely fact that another error occurs) but this
    // manager will continue to retry until the update succeeds.
    public func updateLocalProfile(
        profileGivenName: OptionalChange<OWSUserProfile.NameComponent>,
        profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>,
        profileBio: OptionalChange<String?>,
        profileBioEmoji: OptionalChange<String?>,
        profileAvatarData: OptionalAvatarChange<Data?>,
        visibleBadgeIds: OptionalChange<[String]>,
        unsavedRotatedProfileKey: Aes256Key?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        tx: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        assert(CurrentAppContext().isMainApp)

        let update = enqueueProfileUpdate(
            profileGivenName: profileGivenName,
            profileFamilyName: profileFamilyName,
            profileBio: profileBio,
            profileBioEmoji: profileBioEmoji,
            profileAvatarData: profileAvatarData,
            visibleBadgeIds: visibleBadgeIds,
            userProfileWriter: userProfileWriter,
            tx: tx
        )

        let (promise, future) = Promise<Void>.pending()
        pendingUpdateRequests.update {
            $0.append(ProfileUpdateRequest(
                requestId: update.id,
                requestParameters: .init(profileKey: unsavedRotatedProfileKey, future: future),
                authedAccount: authedAccount
            ))
        }
        tx.addAsyncCompletionOnMain {
            self._updateProfileOnServiceIfNecessary()
        }
        return promise
    }

    public func reuploadLocalProfile(authedAccount: AuthedAccount) {
        let uploadPromise = SSKEnvironment.shared.databaseStorageRef.write { tx in
            return reuploadLocalProfile(
                unsavedRotatedProfileKey: nil,
                mustReuploadAvatar: false,
                authedAccount: authedAccount,
                tx: tx.asV2Write
            )
        }
        Task {
            do {
                try await uploadPromise.awaitable()
                Logger.info("Done.")
            } catch where error.isNetworkFailureOrTimeout {
                Logger.warn("\(error)")
            } catch {
                owsFailDebug("\(error)")
            }
        }
    }

    // This will re-upload the existing local profile state.
    public func reuploadLocalProfile(
        unsavedRotatedProfileKey: Aes256Key?,
        mustReuploadAvatar: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        Logger.info("")

        let profileChanges = currentPendingProfileChanges(tx: SDSDB.shimOnlyBridge(tx))
        return updateLocalProfile(
            profileGivenName: .noChange,
            profileFamilyName: .noChange,
            profileBio: .noChange,
            profileBioEmoji: .noChange,
            profileAvatarData: mustReuploadAvatar ? .noChangeButMustReupload : .noChange,
            visibleBadgeIds: .noChange,
            unsavedRotatedProfileKey: unsavedRotatedProfileKey,
            userProfileWriter: profileChanges?.userProfileWriter ?? .reupload,
            authedAccount: authedAccount,
            tx: SDSDB.shimOnlyBridge(tx)
        )
    }

    // MARK: -

    public func allWhitelistedAddresses(tx: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        var addresses = Set<SignalServiceAddress>()
        for serviceIdString in whitelistedServiceIdsStore.allKeys(transaction: tx.asV2Read) {
            addresses.insert(SignalServiceAddress(serviceIdString: serviceIdString))
        }
        for phoneNumber in whitelistedPhoneNumbersStore.allKeys(transaction: tx.asV2Read) {
            addresses.insert(SignalServiceAddress.legacyAddress(serviceId: nil, phoneNumber: phoneNumber))
        }

        return Array(addresses)
    }

    public func allWhitelistedRegisteredAddresses(tx: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        return allWhitelistedAddresses(tx: tx).lazy.compactMap { address in
            guard
                let recipient = DependenciesBridge.shared.recipientDatabaseTable
                    .fetchRecipient(address: address, tx: tx.asV2Read),
                recipient.isRegistered
            else {
                return nil
            }

            return recipient.address
        }
    }

    // MARK: -

    @objc
    internal func rotateLocalProfileKeyIfNecessary() {
        DispatchQueue.global().async {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
                return
            }
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                self.rotateProfileKeyIfNecessary(tx: tx)
            }
        }
    }

    private func rotateProfileKeyIfNecessary(tx: SDSAnyWriteTransaction) {
        if CurrentAppContext().isNSE || !appReadiness.isAppReady {
            return
        }

        let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read)
        guard
            tsRegistrationState.isRegisteredPrimaryDevice
        else {
            owsFailDebug("Not rotating profile key on unregistered and/or non-primary device")
            return
        }

        let lastGroupProfileKeyCheckTimestamp = self.lastGroupProfileKeyCheckTimestamp(tx: tx)
        let triggers = [
            self.blocklistRotationTriggerIfNeeded(tx: tx),
            self.recipientHidingTriggerIfNeeded(tx: tx),
            self.leaveGroupTriggerIfNeeded(tx: tx)
        ].compacted()

        guard !triggers.isEmpty else {
            // No need to rotate the profile key.
            if tsRegistrationState.isPrimaryDevice ?? true {
                // But if it's been more than a week since we checked that our groups are up to date, schedule that.
                if -(lastGroupProfileKeyCheckTimestamp?.timeIntervalSinceNow ?? 0) > kWeekInterval {
                    SSKEnvironment.shared.groupsV2Ref.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: tx)
                    self.setLastGroupProfileKeyCheckTimestamp(tx: tx)
                    tx.addAsyncCompletionOffMain {
                        SSKEnvironment.shared.groupsV2Ref.processProfileKeyUpdates()
                    }
                }
            }
            return
        }

        tx.addAsyncCompletionOffMain {
            self.rotateProfileKey(triggers: triggers, authedAccount: AuthedAccount.implicit())
        }
    }

    private enum RotateProfileKeyTrigger {
        /// We need to rotate because one or more whitelist members is also on the blocklist.
        /// Those members may be phone numbers, ACIs, PNIs, or groupIds, which are provided.
        /// Once rotation is complete, these members should be removed from the whitelist;
        /// their presence in the whitelist _and_ blocklist is what durably determines a rotation
        /// is needed, so prematurely removing them and then failing to rotate means we won't retry.
        case blocklistChange(BlocklistChange)

        struct BlocklistChange {
            let phoneNumbers: [String]
            let serviceIds: [ServiceId]
            let groupIds: [Data]
        }

        /// When we hide a recipient, we immediately update the whitelist and asynchronously
        /// do a rotation. The date is when we set this trigger; if we _started_ a rotation
        /// after this date, the condition is satisfied when the rotation completes. Otherwise
        /// a rotation is needed.
        case recipientHiding(Date)

        /// When we leave a group, that group had a hidden/blocked recipient, and we have no
        /// other groups in common with that recipient, we rotate (so they lose access to our latest
        /// profile key).
        /// The date is when we set this trigger; if we _started_ a rotation after this date, the
        /// condition is satisfied when the rotation completes. Otherwise a rotation is needed.
        case leftGroupWithHiddenOrBlockedRecipient(Date)
    }

    private func blocklistRotationTriggerIfNeeded(tx: SDSAnyReadTransaction) -> RotateProfileKeyTrigger? {
        let victimPhoneNumbers = self.blockedPhoneNumbersInWhitelist(tx: tx)
        let victimServiceIds = self.blockedServiceIdsInWhitelist(tx: tx)
        let victimGroupIds = self.blockedGroupIDsInWhitelist(tx: tx)

        if victimPhoneNumbers.isEmpty, victimServiceIds.isEmpty, victimGroupIds.isEmpty {
            // No need to rotate the profile key.
            return nil
        }
        return .blocklistChange(.init(
            phoneNumbers: victimPhoneNumbers,
            serviceIds: victimServiceIds,
            groupIds: victimGroupIds
        ))
    }

    private func recipientHidingTriggerIfNeeded(tx: SDSAnyReadTransaction) -> RotateProfileKeyTrigger? {
        // If it's not nil, we should rotate. After rotating, we always write nil (if it succeeded),
        // so presence is the only trigger.
        // The actual date value is only used to disambiguate if a _new_ trigger got added while rotating.
        guard let triggerDate = self.recipientHidingTriggerTimestamp(tx: tx) else {
            return nil
        }
        return .recipientHiding(triggerDate)
    }

    private func leaveGroupTriggerIfNeeded(tx: SDSAnyReadTransaction) -> RotateProfileKeyTrigger? {
        // If it's not nil, we should rotate. After rotating, we always write nil (if it succeeded),
        // so presence is the only trigger.
        // The actual date value is only used to disambiguate if a _new_ trigger got added while rotating.
        guard let triggerDate = self.leaveGroupTriggerTimestamp(tx: tx) else {
            return nil
        }
        return .leftGroupWithHiddenOrBlockedRecipient(triggerDate)
    }

    @discardableResult
    private func rotateProfileKey(
        triggers: [RotateProfileKeyTrigger],
        authedAccount: AuthedAccount
    ) -> Promise<Void> {
        guard !isRotatingProfileKey else {
            return .value(())
        }

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
            return Promise(error: OWSAssertionError("tsAccountManager.isRegistered was unexpectedly false"))
        }

        isRotatingProfileKey = true

        let rotationStartDate = Date()

        Logger.info("Beginning profile key rotation.")

        // The order of operations here is very important to prevent races between
        // when we rotate our profile key and reupload our profile. It's essential
        // we avoid a case where other devices are operating with a *new* profile
        // key that we have yet to upload a profile for.

        return Promise.wrapAsync {
            Logger.info("Reuploading profile with new profile key")

            // We re-upload our local profile with the new profile key *before* we
            // persist it. This is safe, because versioned profiles allow other clients
            // to continue using our old profile key with the old version of our
            // profile. It is possible this operation will fail, in which case we will
            // try to rotate your profile key again on the next app launch or blocklist
            // change and continue to use the old profile key.

            let newProfileKey = Aes256Key.generateRandom()
            let uploadPromise = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                self.reuploadLocalProfile(
                    unsavedRotatedProfileKey: newProfileKey,
                    mustReuploadAvatar: true,
                    authedAccount: authedAccount,
                    tx: tx.asV2Write
                )
            }
            try await uploadPromise.awaitable()

            guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
                throw OWSAssertionError("Missing localAci.")
            }

            Logger.info("Persisting rotated profile key and kicking off subsequent operations.")

            let needsAnotherRotation = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                self.setLocalProfileKey(
                    newProfileKey,
                    userProfileWriter: .localUser,
                    transaction: tx
                )

                // Whenever a user's profile key changes, we need to fetch a new profile
                // key credential for them.
                SSKEnvironment.shared.versionedProfilesRef.clearProfileKeyCredential(for: AciObjC(localAci), transaction: tx)

                // We schedule the updates here but process them below using
                // processProfileKeyUpdates. It's more efficient to process them after the
                // intermediary steps are done.
                SSKEnvironment.shared.groupsV2Ref.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: tx)

                var needsAnotherRotation = false

                triggers.forEach { trigger in
                    switch trigger {
                    case .blocklistChange(let values):
                        self.didRotateProfileKeyFromBlocklistTrigger(values, tx: tx)
                    case .recipientHiding(let triggerDate):
                        needsAnotherRotation = needsAnotherRotation || self.didRotateProfileKeyFromHidingTrigger(
                            rotationStartDate: rotationStartDate,
                            triggerDate: triggerDate,
                            tx: tx
                        )
                    case .leftGroupWithHiddenOrBlockedRecipient(let triggerDate):
                        needsAnotherRotation = needsAnotherRotation || self.didRotateProfileKeyFromLeaveGroupTrigger(
                            rotationStartDate: rotationStartDate,
                            triggerDate: triggerDate,
                            tx: tx
                        )
                    }
                }

                return needsAnotherRotation
            }

            Logger.info("Updating account attributes after profile key rotation.")
            try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: authedAccount)

            Logger.info("Completed profile key rotation.")
            SSKEnvironment.shared.groupsV2Ref.processProfileKeyUpdates()

            await MainActor.run {
                self.isRotatingProfileKey = false
            }
            if needsAnotherRotation {
                self.rotateLocalProfileKeyIfNecessary()
            }
        }
    }

    private func didRotateProfileKeyFromBlocklistTrigger(
        _ trigger: RotateProfileKeyTrigger.BlocklistChange,
        tx: SDSAnyWriteTransaction
    ) {
        // It's absolutely essential that these values are persisted in the same transaction
        // in which we persist our new profile key, since storing them is what marks the
        // profile key rotation as "complete" (removing newly blocked users from the whitelist).
        self.whitelistedPhoneNumbersStore.removeValues(
            forKeys: trigger.phoneNumbers,
            transaction: tx.asV2Write
        )
        self.whitelistedServiceIdsStore.removeValues(
            forKeys: trigger.serviceIds.map { $0.serviceIdUppercaseString },
            transaction: tx.asV2Write
        )
        self.whitelistedGroupsStore.removeValues(
            forKeys: trigger.groupIds.map { self.groupKey(groupId: $0) },
            transaction: tx.asV2Write
        )
    }

    // Returns true if another rotation is needed.
    private func didRotateProfileKeyFromHidingTrigger(
        rotationStartDate: Date,
        triggerDate: Date,
        tx: SDSAnyWriteTransaction
    ) -> Bool {
        // Fetch the latest trigger date, it might have changed if we triggered
        // a rotation again.
        guard let latestTriggerDate = self.recipientHidingTriggerTimestamp(tx: tx) else {
            // If it's been wiped, we are good to go.
            return false
        }
        if rotationStartDate > latestTriggerDate {
            // We can wipe; we started rotating after the trigger came in.
            self.setRecipientHidingTriggerTimestamp(nil, tx: tx)
            return false
        }
        // We need another rotation.
        return true
    }

    // Returns true if another rotation is needed.
    private func didRotateProfileKeyFromLeaveGroupTrigger(
        rotationStartDate: Date,
        triggerDate: Date,
        tx: SDSAnyWriteTransaction
    ) -> Bool {
        // Fetch the latest trigger date, it might have changed if we triggered
        // a rotation again.
        guard let latestTriggerDate = self.leaveGroupTriggerTimestamp(tx: tx) else {
            // If it's been wiped, we are good to go.
            return false
        }
        if rotationStartDate > latestTriggerDate {
            // We can wipe; we started rotating after the trigger came in.
            self.setLeaveGroupTriggerTimestamp(nil, tx: tx)
            return false
        }
        // We need another rotation.
        return true
    }

    private func blockedPhoneNumbersInWhitelist(tx: SDSAnyReadTransaction) -> [String] {
        let allWhitelistedNumbers = whitelistedPhoneNumbersStore.allKeys(transaction: tx.asV2Read)

        return allWhitelistedNumbers.filter { candidate in
            let address = SignalServiceAddress.legacyAddress(serviceId: nil, phoneNumber: candidate)
            return SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(address, transaction: tx)
        }
    }

    private func blockedServiceIdsInWhitelist(tx: SDSAnyReadTransaction) -> [ServiceId] {
        let allWhitelistedServiceIds = whitelistedServiceIdsStore.allKeys(transaction: tx.asV2Read).compactMap {
            try? ServiceId.parseFrom(serviceIdString: $0)
        }

        return allWhitelistedServiceIds.filter { candidate in
            return SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(candidate), transaction: tx)
        }
    }

    private func blockedGroupIDsInWhitelist(tx: SDSAnyReadTransaction) -> [Data] {
        let allWhitelistedGroupKeys = whitelistedGroupsStore.allKeys(transaction: tx.asV2Read)

        return allWhitelistedGroupKeys.lazy
            .compactMap { self.groupIdForGroupKey($0) }
            .filter { SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked($0, transaction: tx) }
    }

    private func groupIdForGroupKey(_ groupKey: String) -> Data? {
        guard let groupId = Data.data(fromHex: groupKey) else { return nil }

        if GroupManager.isValidGroupIdOfAnyKind(groupId) {
            return groupId
        } else {
            owsFailDebug("Parsed group id has unexpected length: \(groupId.hexadecimalString) (\(groupId.count))")
            return nil
        }
    }

    @objc
    func swift_normalizeRecipientInProfileWhitelist(_ recipient: SignalRecipient, tx: SDSAnyWriteTransaction) {
        Self.swift_normalizeRecipientInProfileWhitelist(
            recipient,
            serviceIdStore: whitelistedServiceIdsStore,
            phoneNumberStore: whitelistedPhoneNumbersStore,
            tx: tx.asV2Write
        )
    }

    public static func swift_normalizeRecipientInProfileWhitelist(
        _ recipient: SignalRecipient,
        serviceIdStore: KeyValueStore,
        phoneNumberStore: KeyValueStore,
        tx: DBWriteTransaction
    ) {
        // First, we figure out which identifiers are whitelisted.
        let orderedIdentifiers: [(store: KeyValueStore, key: String, isInWhitelist: Bool)] = [
            (serviceIdStore, recipient.aci?.serviceIdUppercaseString),
            (phoneNumberStore, recipient.phoneNumber?.stringValue),
            (serviceIdStore, recipient.pni?.serviceIdUppercaseString)
        ].compactMap { (store, key) -> (KeyValueStore, String, Bool)? in
            guard let key else { return nil }
            return (store, key, store.hasValue(key, transaction: tx))
        }

        guard let preferredIdentifier = orderedIdentifiers.first else {
            return
        }

        // If any identifier is in the whitelist, make sure the preferred
        // identifier is in the whitelist.
        let isAnyInWhitelist = orderedIdentifiers.contains(where: { $0.isInWhitelist })
        if isAnyInWhitelist {
            if !preferredIdentifier.isInWhitelist {
                preferredIdentifier.store.setBool(true, key: preferredIdentifier.key, transaction: tx)
            }
        } else {
            if preferredIdentifier.isInWhitelist {
                preferredIdentifier.store.removeValue(forKey: preferredIdentifier.key, transaction: tx)
            }
        }

        // Always remove all the other identifiers from the whitelist. If the user
        // should be in the whitelist, we add the preferred identifier above.
        for remainingIdentifier in orderedIdentifiers.dropFirst() {
            if remainingIdentifier.isInWhitelist {
                remainingIdentifier.store.removeValue(forKey: remainingIdentifier.key, transaction: tx)
            }
        }
    }

    @objc
    class func updateStorageServiceIfNecessary() {
        guard
            CurrentAppContext().isMainApp,
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice
        else {
            return
        }

        let hasUpdated = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            storageServiceStore.getBool(Self.hasUpdatedStorageServiceKey,
                                        defaultValue: false,
                                        transaction: transaction.asV2Read)
        }

        guard !hasUpdated else {
            return
        }

        if SSKEnvironment.shared.profileManagerRef.localProfileAvatarData != nil {
            Logger.info("Scheduling a backup.")

            // Schedule a backup.
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        }

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            storageServiceStore.setBool(true,
                                        key: Self.hasUpdatedStorageServiceKey,
                                        transaction: transaction.asV2Write)
        }
    }

    private static let storageServiceStore = KeyValueStore(collection: "OWSProfileManager.storageServiceStore")
    private static let hasUpdatedStorageServiceKey = "hasUpdatedStorageServiceKey"

    // MARK: - Other User's Profiles

    /// Updates the profile key, optionally fetching the latest profile.
    public func setProfileKeyData(
        _ profileKeyData: Data,
        for serviceId: ServiceId,
        onlyFillInIfMissing: Bool,
        shouldFetchProfile: Bool,
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) {
        let address = OWSUserProfile.insertableAddress(serviceId: serviceId, localIdentifiers: localIdentifiers)

        guard let profileKey = Aes256Key(data: profileKeyData) else {
            owsFailDebug("Invalid profile key data for \(serviceId).")
            return
        }

        let userProfile = OWSUserProfile.getOrBuildUserProfile(
            for: address,
            userProfileWriter: userProfileWriter,
            tx: SDSDB.shimOnlyBridge(tx)
        )

        if onlyFillInIfMissing, userProfile.profileKey != nil {
            return
        }

        if profileKey.keyData == userProfile.profileKey?.keyData {
            return
        }

        if let aci = serviceId as? Aci {
            // Whenever a user's profile key changes, we need to fetch a new
            // profile key credential for them.
            SSKEnvironment.shared.versionedProfilesRef.clearProfileKeyCredential(for: AciObjC(aci), transaction: SDSDB.shimOnlyBridge(tx))
        }

        // If this is the profile for the local user, we always want to defer to local state
        // so skip the update profile for address call.
        if case .otherUser(let serviceId) = address {
            SSKEnvironment.shared.udManagerRef.setUnidentifiedAccessMode(.unknown, for: serviceId, tx: SDSDB.shimOnlyBridge(tx))
            if shouldFetchProfile {
                tx.addSyncCompletion {
                    let profileFetcher = SSKEnvironment.shared.profileFetcherRef
                    _ = profileFetcher.fetchProfileSync(for: serviceId, authedAccount: authedAccount)
                }
            }
        }

        userProfile.update(
            profileKey: .setTo(profileKey),
            userProfileWriter: userProfileWriter,
            transaction: SDSDB.shimOnlyBridge(tx),
            completion: nil
        )
    }

    public func fillInProfileKeys(
        allProfileKeys: [Aci: Data],
        authoritativeProfileKeys: [Aci: Data],
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
        for (aci, profileKey) in authoritativeProfileKeys {
            setProfileKeyData(
                profileKey,
                for: aci,
                onlyFillInIfMissing: false,
                shouldFetchProfile: true,
                userProfileWriter: userProfileWriter,
                localIdentifiers: localIdentifiers,
                authedAccount: .implicit(),
                tx: tx
            )
        }
        for (aci, profileKey) in allProfileKeys {
            if authoritativeProfileKeys[aci] != nil {
                continue
            }
            setProfileKeyData(
                profileKey,
                for: aci,
                onlyFillInIfMissing: true,
                shouldFetchProfile: true,
                userProfileWriter: userProfileWriter,
                localIdentifiers: localIdentifiers,
                authedAccount: .implicit(),
                tx: tx
            )
        }
    }

    // MARK: - Bulk Fetching

    @objc
    func _getUserProfile(for address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> OWSUserProfile? {
        // TODO: Don't reach out to global state.
        if address.isLocalAddress {
            // For "local reads", use the local user profile.
            return getLocalUserProfile(tx)
        } else {
            return OWSUserProfile.getUserProfiles(for: [.otherUser(address)], tx: tx).first!
        }
    }

    public func fetchUserProfiles(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        return Refinery<SignalServiceAddress, OWSUserProfile>(addresses).refine(condition: { address in
            // TODO: Don't reach out to global state.
            return address.isLocalAddress
        }, then: { localAddresses in
            lazy var profile = { self.getLocalUserProfile(tx) }()
            return localAddresses.lazy.map { _ in profile }
        }, otherwise: { otherAddresses in
            return OWSUserProfile.getUserProfiles(for: otherAddresses.map { .otherUser($0) }, tx: tx)
        }).values
    }

    // MARK: -

    private class var avatarUrlSession: OWSURLSessionProtocol {
        return SSKEnvironment.shared.signalServiceRef.urlSessionForCdn(cdnNumber: 0, maxResponseSize: nil)
    }

    // MARK: -

    @objc
    public func updateProfileOnServiceIfNecessary(authedAccount: AuthedAccount) {
        switch _updateProfileOnServiceIfNecessary() {
        case .notReady, .updating:
            return
        case .notNeeded:
            repairAvatarIfNeeded(authedAccount: authedAccount)
        }
    }

    private enum UpdateProfileStatus {
        case notReady
        case notNeeded
        case updating
    }

    fileprivate struct ProfileUpdateRequest {
        var requestId: UUID
        var requestParameters: Parameters
        var authedAccount: AuthedAccount

        struct Parameters {
            var profileKey: Aes256Key?
            var future: Future<Void>
        }
    }

    @discardableResult
    private func _updateProfileOnServiceIfNecessary(retryDelay: TimeInterval = 1) -> UpdateProfileStatus {
        AssertIsOnMainThread()

        guard appReadiness.isAppReady else {
            return .notReady
        }
        guard !isUpdatingProfileOnService else {
            // Avoid having two redundant updates in flight at the same time.
            return .notReady
        }

        let profileChanges = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return currentPendingProfileChanges(tx: tx)
        }
        guard let profileChanges else {
            return .notNeeded
        }

        guard let (parameters, authedAccount) = processProfileUpdateRequests(upThrough: profileChanges.id) else {
            return .notReady
        }

        isUpdatingProfileOnService = true

        let backgroundTask = OWSBackgroundTask(label: #function)
        Task { @MainActor in
            // We must be on the MainActor to touch isUpdatingProfileOnService.
            defer {
                isUpdatingProfileOnService = false
                backgroundTask.end()
            }
            do {
                try await updateProfileOnService(
                    profileChanges: profileChanges,
                    newProfileKey: parameters?.profileKey,
                    authedAccount: authedAccount
                )
                DispatchQueue.global().async {
                    parameters?.future.resolve()
                }
                DispatchQueue.main.async {
                    self._updateProfileOnServiceIfNecessary()
                }
            } catch {
                DispatchQueue.global().async {
                    parameters?.future.reject(error)
                }
                Logger.warn("Retrying profile update after \(retryDelay)s due to error: \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                    self._updateProfileOnServiceIfNecessary(retryDelay: retryDelay * 2)
                }
            }
        }

        return .updating
    }

    /// Searches `pendingUpdateRequests` for a match; cancels dropped requests.
    ///
    /// Processes `pendingUpdateRequests` while searching for `requestId`. If it
    /// finds a pending request with `requestId`, it will cancel any preceding
    /// requests that are now obsolete.
    ///
    /// - Returns: The `Future` and `AuthedAccount` to use for `requestId`. If
    /// `requestId` can't be sent right now, returns `nil`. We can't send
    /// requests if we can't authenticate with the server. We assume we can
    /// authenticate when we're registered or if the request's `authedAccount`
    /// contains explicit credentials.
    private func processProfileUpdateRequests(upThrough requestId: UUID) -> (ProfileUpdateRequest.Parameters?, AuthedAccount)? {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let isRegistered = tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered

        // Find the AuthedAccount & Future for the request. This will generally
        // exist for the initial request but will be nil for any retries.
        let pendingRequests: (canceledRequests: [ProfileUpdateRequest], result: (ProfileUpdateRequest.Parameters?, AuthedAccount)?)
        pendingRequests = pendingUpdateRequests.update { mutableRequests in
            let canceledRequests: [ProfileUpdateRequest]
            let currentRequest: ProfileUpdateRequest?
            if let requestIndex = mutableRequests.firstIndex(where: { $0.requestId == requestId }) {
                canceledRequests = Array(mutableRequests.prefix(upTo: requestIndex))
                currentRequest = mutableRequests[requestIndex]
                mutableRequests = Array(mutableRequests[requestIndex...])
            } else {
                canceledRequests = []
                currentRequest = nil
            }

            let authedAccount = currentRequest?.authedAccount ?? .implicit()
            switch authedAccount.info {
            case .implicit where isRegistered, .explicit:
                mutableRequests = Array(mutableRequests.dropFirst())
                return (canceledRequests, (currentRequest?.requestParameters, authedAccount))
            case .implicit:
                return (canceledRequests, nil)
            }
        }

        for canceledRequest in pendingRequests.canceledRequests {
            canceledRequest.requestParameters.future.reject(OWSGenericError("Canceled because a new request was enqueued."))
        }

        return pendingRequests.result
    }

    private static var avatarRepairPromise: Promise<Void>?

    private func repairAvatarIfNeeded(authedAccount: AuthedAccount) {
        guard CurrentAppContext().isMainApp else {
            return
        }

        dispatchPrecondition(condition: .onQueue(.main))
        guard Self.avatarRepairPromise == nil else {
            // Already have a repair outstanding.
            return
        }

        // Have already repaired?

        guard avatarRepairNeeded() else {
            return
        }
        guard
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? false,
            self.localProfileAvatarData != nil
        else {
            SSKEnvironment.shared.databaseStorageRef.write { tx in clearAvatarRepairNeeded(tx: tx) }
            return
        }

        Self.avatarRepairPromise = Promise.wrapAsync { @MainActor in
            defer {
                Self.avatarRepairPromise = nil
            }
            do {
                let uploadPromise = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                    return self.reuploadLocalProfile(
                        unsavedRotatedProfileKey: nil,
                        mustReuploadAvatar: true,
                        authedAccount: authedAccount,
                        tx: tx.asV2Write
                    )
                }
                try await uploadPromise.awaitable()
                Logger.info("Avatar repair succeeded.")
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in self.clearAvatarRepairNeeded(tx: tx) }
            } catch {
                Logger.warn("Avatar repair failed: \(error)")
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in self.incrementAvatarRepairAttempts(tx: tx) }
            }
        }
    }

    private static let maxAvatarRepairAttempts = 5

    private func avatairRepairAttemptCount(_ transaction: SDSAnyReadTransaction) -> Int {
        let store = KeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
        return store.getInt(GRDBSchemaMigrator.avatarRepairAttemptCount,
                            defaultValue: Self.maxAvatarRepairAttempts,
                            transaction: transaction.asV2Read)
    }

    private func avatarRepairNeeded() -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let count = avatairRepairAttemptCount(transaction)
            return count < Self.maxAvatarRepairAttempts
        }
    }

    private func incrementAvatarRepairAttempts(tx: SDSAnyWriteTransaction) {
        let store = KeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
        store.setInt(avatairRepairAttemptCount(tx) + 1, key: GRDBSchemaMigrator.avatarRepairAttemptCount, transaction: tx.asV2Write)
    }

    private func clearAvatarRepairNeeded(tx: SDSAnyWriteTransaction) {
        let store = KeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
        store.removeValue(forKey: GRDBSchemaMigrator.avatarRepairAttemptCount, transaction: tx.asV2Write)
    }

    private func updateProfileOnService(
        profileChanges: PendingProfileUpdate,
        newProfileKey: Aes256Key?,
        authedAccount: AuthedAccount
    ) async throws {
        do {
            let avatarUpdate = try await buildAvatarUpdate(
                avatarChange: profileChanges.profileAvatarData,
                authedAccount: authedAccount
            )

            // We capture the local user profile early to eliminate the risk of opening
            // a transaction within a transaction.
            let userProfile = SSKEnvironment.shared.profileManagerImplRef.localUserProfile
            guard let profileKey = newProfileKey ?? userProfile.profileKey else {
                throw OWSAssertionError("Can't upload profile without profileKey.")
            }

            // It's important that the value we compute for
            // `newGivenName`/`newFamilyName` exactly match what we put in our
            // encrypted profile. If they don't match (eg one trims the value and the
            // other doesn't), then `LocalProfileChecker` may enter an infinite loop
            // trying to fix the profile.

            let newGivenName: OWSUserProfile.NameComponent?
            switch profileChanges.profileGivenName {
            case .setTo(let newValue):
                newGivenName = newValue
            case .noChange:
                // This is the *only* place that can clear our own name, and it only does
                // so when the name we think we have (which should be valid) isn't valid.
                newGivenName = userProfile.givenName.flatMap { OWSUserProfile.NameComponent(truncating: $0) }
            }
            let newFamilyName = profileChanges.profileFamilyName.orExistingValue(
                userProfile.familyName.flatMap { OWSUserProfile.NameComponent(truncating: $0) }
            )
            let newBio = profileChanges.profileBio.orExistingValue(userProfile.bio)
            let newBioEmoji = profileChanges.profileBioEmoji.orExistingValue(userProfile.bioEmoji)
            let newVisibleBadgeIds = profileChanges.visibleBadgeIds.orExistingValue(userProfile.visibleBadges.map { $0.badgeId })

            let versionedUpdate = try await SSKEnvironment.shared.versionedProfilesRef.updateProfile(
                profileGivenName: newGivenName,
                profileFamilyName: newFamilyName,
                profileBio: newBio,
                profileBioEmoji: newBioEmoji,
                profileAvatarMutation: avatarUpdate.remoteMutation,
                visibleBadgeIds: newVisibleBadgeIds,
                profileKey: profileKey,
                authedAccount: authedAccount
            )
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                self.tryToDequeueProfileChanges(profileChanges, tx: tx)
                // Apply the changes to our local profile.
                let userProfile = OWSUserProfile.getOrBuildUserProfile(
                    for: .localUser,
                    userProfileWriter: .localUser,
                    tx: tx
                )
                userProfile.update(
                    givenName: .setTo(newGivenName?.stringValue.rawValue),
                    familyName: .setTo(newFamilyName?.stringValue.rawValue),
                    bio: .setTo(newBio),
                    bioEmoji: .setTo(newBioEmoji),
                    avatarUrlPath: .setTo(versionedUpdate.avatarUrlPath.orExistingValue(userProfile.avatarUrlPath)),
                    avatarFileName: .setTo(avatarUpdate.filenameChange.orExistingValue(userProfile.avatarFileName)),
                    userProfileWriter: profileChanges.userProfileWriter,
                    transaction: tx,
                    completion: nil
                )
                // Notify all our devices that the profile has changed.
                let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read)
                if tsRegistrationState.isRegistered {
                    SSKEnvironment.shared.syncManagerRef.sendFetchLatestProfileSyncMessage(tx: tx)
                }
            }
            // If we're changing the profile key, then the normal "fetch our profile"
            // method will fail because it will the just-obsoleted profile key.
            if newProfileKey == nil {
                _ = try await fetchLocalUsersProfile(authedAccount: authedAccount).awaitable()
            }
        } catch let error where error.isNetworkFailureOrTimeout {
            // We retry network errors forever (with exponential backoff).
            throw error
        } catch {
            // Other errors cause us to give up immediately.
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in self.tryToDequeueProfileChanges(profileChanges, tx: tx) }
            Logger.error("Discarding profile update due to fatal error: \(error)")
            throw error
        }
    }

    /// Computes necessary changes to the avatar.
    ///
    /// Most fields are re-encrypted with every update. However, the avatar can
    /// be large, so we only update it if absolutely necessary. We must update
    /// the profile avatar in three cases:
    ///   (1) The avatar has changed (duh!).
    ///   (2) The profile key has changed.
    ///   (3) The remote avatar doesn't match the local avatar.
    /// In the first case, we'll always have the new avatar because we're
    /// actively changing it. In the latter case, another device may have
    /// changed it, so we may need to download it to re-encrypt it.
    private func buildAvatarUpdate(
        avatarChange: OptionalAvatarChange<Data?>,
        authedAccount: AuthedAccount
    ) async throws -> (remoteMutation: VersionedProfileAvatarMutation, filenameChange: OptionalChange<String?>) {
        switch avatarChange {
        case .setTo(let newAvatar):
            // This is case (1). It's also case (2) when we're also changing the avatar.
            if let newAvatar {
                let avatarFilename = try writeProfileAvatarToDisk(avatarData: newAvatar)
                return (.changeAvatar(newAvatar), .setTo(avatarFilename))
            }
            return (.clearAvatar, .setTo(nil))
        case .noChangeButMustReupload:
            // This is case (2) and (3).
            do {
                try await downloadAndDecryptLocalUserAvatarIfNeeded(authedAccount: authedAccount)
            } catch where !error.isNetworkFailureOrTimeout {
                // Ignore the error because it's not likely to go away if we retry. If we
                // can't decrypt the existing avatar, then we don't really have any choice
                // other than blowing it away.
                Logger.warn("Dropping unfetchable avatar: \(error)")
            }
            if let avatarFilename = localUserProfile.avatarFileName, let avatarData = localProfileAvatarData {
                return (.changeAvatar(avatarData), .setTo(avatarFilename))
            }
            return (.clearAvatar, .setTo(nil))
        case .noChange:
            // We aren't changing the avatar, so use the existing value.
            if localUserProfile.avatarUrlPath != nil {
                return (.keepAvatar, .noChange)
            }
            return (.clearAvatar, .setTo(nil))
        }
    }

    private func writeProfileAvatarToDisk(avatarData: Data) throws -> String {
        let filename = OWSUserProfile.generateAvatarFilename()
        let filePath = OWSUserProfile.profileAvatarFilePath(for: filename)
        do {
            try avatarData.write(to: URL(fileURLWithPath: filePath), options: [.atomic])
        } catch {
            throw OWSError(error: .avatarWriteFailed, description: "Avatar write failed.", isRetryable: false)
        }
        return filename
    }

    // MARK: - Update Queue

    private static let kPendingProfileUpdateKey = "kPendingProfileUpdateKey"

    private func enqueueProfileUpdate(
        profileGivenName: OptionalChange<OWSUserProfile.NameComponent>,
        profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>,
        profileBio: OptionalChange<String?>,
        profileBioEmoji: OptionalChange<String?>,
        profileAvatarData: OptionalAvatarChange<Data?>,
        visibleBadgeIds: OptionalChange<[String]>,
        userProfileWriter: UserProfileWriter,
        tx: SDSAnyWriteTransaction
    ) -> PendingProfileUpdate {
        let oldChanges = currentPendingProfileChanges(tx: tx)
        let newChanges = PendingProfileUpdate(
            profileGivenName: profileGivenName.orElseIfNoChange(oldChanges?.profileGivenName ?? .noChange),
            profileFamilyName: profileFamilyName.orElseIfNoChange(oldChanges?.profileFamilyName ?? .noChange),
            profileBio: profileBio.orElseIfNoChange(oldChanges?.profileBio ?? .noChange),
            profileBioEmoji: profileBioEmoji.orElseIfNoChange(oldChanges?.profileBioEmoji ?? .noChange),
            profileAvatarData: { () -> OptionalAvatarChange<Data?> in
                let newValue = profileAvatarData
                // If newValue isn't as important as oldValue, prefer oldValue. If there's
                // a tie, prefer newValue.
                if let oldValue = oldChanges?.profileAvatarData, newValue.isLessImportantThan(oldValue) {
                    return oldValue
                }
                return newValue
            }(),
            visibleBadgeIds: visibleBadgeIds.orElseIfNoChange(oldChanges?.visibleBadgeIds ?? .noChange),
            userProfileWriter: userProfileWriter
        )
        settingsStore.setObject(newChanges, key: Self.kPendingProfileUpdateKey, transaction: tx.asV2Write)
        return newChanges
    }

    private func currentPendingProfileChanges(tx: SDSAnyReadTransaction) -> PendingProfileUpdate? {
        return settingsStore.getObject(Self.kPendingProfileUpdateKey, ofClass: PendingProfileUpdate.self, transaction: tx.asV2Read)
    }

    private func isCurrentPendingProfileChanges(_ profileChanges: PendingProfileUpdate, tx: SDSAnyReadTransaction) -> Bool {
        guard let databaseValue = currentPendingProfileChanges(tx: tx) else {
            return false
        }
        return profileChanges.hasSameIdAs(databaseValue)
    }

    private func tryToDequeueProfileChanges(_ profileChanges: PendingProfileUpdate, tx: SDSAnyWriteTransaction) {
        guard isCurrentPendingProfileChanges(profileChanges, tx: tx) else {
            Logger.warn("Ignoring stale update completion.")
            return
        }
        settingsStore.removeValue(forKey: Self.kPendingProfileUpdateKey, transaction: tx.asV2Write)
    }

    /// Rotates the local profile key. Intended specifically
    /// for the use case of recipient hiding.
    ///
    /// - Parameter tx: The transaction to use for this operation.
    @objc
    func rotateProfileKeyUponRecipientHideObjC(tx: SDSAnyWriteTransaction) {
        let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read)
        guard tsRegistrationState.isRegistered else {
            return
        }
        guard tsRegistrationState.isPrimaryDevice ?? false else {
            return
        }
        // We schedule in the NSE by writing state; the actual rotation
        // will bail early, though.
        self.setRecipientHidingTriggerTimestamp(Date(), tx: tx)
        self.rotateProfileKeyIfNecessary(tx: tx)
    }

    @objc
    func forceRotateLocalProfileKeyForGroupDepartureObjc(tx: SDSAnyWriteTransaction) {
        let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read)
        guard tsRegistrationState.isRegistered else {
            return
        }
        guard tsRegistrationState.isPrimaryDevice ?? false else {
            return
        }
        // We schedule in the NSE by writing state; the actual rotation
        // will bail early, though.
        self.setLeaveGroupTriggerTimestamp(Date(), tx: tx)
        self.rotateProfileKeyIfNecessary(tx: tx)
    }

    // MARK: - Profile Key Rotation Metadata

    private static let kLastGroupProfileKeyCheckTimestampKey = "lastGroupProfileKeyCheckTimestamp"

    private func lastGroupProfileKeyCheckTimestamp(tx: SDSAnyReadTransaction) -> Date? {
        return self.metadataStore.getDate(Self.kLastGroupProfileKeyCheckTimestampKey, transaction: tx.asV2Read)
    }

    private func setLastGroupProfileKeyCheckTimestamp(tx: SDSAnyWriteTransaction) {
        return self.metadataStore.setDate(Date(), key: Self.kLastGroupProfileKeyCheckTimestampKey, transaction: tx.asV2Write)
    }

    private static let recipientHidingTriggerTimestampKey = "recipientHidingTriggerTimestampKey"

    private func recipientHidingTriggerTimestamp(tx: SDSAnyReadTransaction) -> Date? {
        return self.metadataStore.getDate(Self.recipientHidingTriggerTimestampKey, transaction: tx.asV2Read)
    }

    private func setRecipientHidingTriggerTimestamp(_ date: Date?, tx: SDSAnyWriteTransaction) {
        guard let date else {
            self.metadataStore.removeValue(forKey: Self.recipientHidingTriggerTimestampKey, transaction: tx.asV2Write)
            return
        }
        return self.metadataStore.setDate(date, key: Self.recipientHidingTriggerTimestampKey, transaction: tx.asV2Write)
    }

    private static let leaveGroupTriggerTimestampKey = "leaveGroupTriggerTimestampKey"

    private func leaveGroupTriggerTimestamp(tx: SDSAnyReadTransaction) -> Date? {
        return self.metadataStore.getDate(Self.leaveGroupTriggerTimestampKey, transaction: tx.asV2Read)
    }

    private func setLeaveGroupTriggerTimestamp(_ date: Date?, tx: SDSAnyWriteTransaction) {
        guard let date else {
            self.metadataStore.removeValue(forKey: Self.leaveGroupTriggerTimestampKey, transaction: tx.asV2Write)
            return
        }
        return self.metadataStore.setDate(date, key: Self.leaveGroupTriggerTimestampKey, transaction: tx.asV2Write)
    }

    // MARK: - Last Messaging Date

    public func didSendOrReceiveMessage(
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
        let userProfileWriter: UserProfileWriter = .metadataUpdate

        let address = OWSUserProfile.insertableAddress(serviceId: serviceId, localIdentifiers: localIdentifiers)
        switch address {
        case .localUser:
            return
        case .otherUser:
            break
        case .legacyUserPhoneNumberFromBackupRestore:
            owsFail("Impossible: could not get this case when constructing an insertable address from a service ID.")
        }
        let userProfile = OWSUserProfile.getOrBuildUserProfile(
            for: address,
            userProfileWriter: userProfileWriter,
            tx: SDSDB.shimOnlyBridge(tx)
        )

        // lastMessagingDate is coarse; we don't need to track every single message
        // sent or received. It is sufficient to update it only when the value
        // changes by more than an hour.
        if let lastMessagingDate = userProfile.lastMessagingDate, abs(lastMessagingDate.timeIntervalSinceNow) < kHourInterval {
            return
        }

        userProfile.update(
            lastMessagingDate: .setTo(Date()),
            userProfileWriter: userProfileWriter,
            transaction: SDSDB.shimOnlyBridge(tx),
            completion: nil
        )
    }
}

// MARK: -

public class PendingProfileUpdate: NSObject, NSSecureCoding {
    let id: UUID

    let profileGivenName: OptionalChange<OWSUserProfile.NameComponent>
    let profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>
    let profileBio: OptionalChange<String?>
    let profileBioEmoji: OptionalChange<String?>
    let profileAvatarData: OptionalAvatarChange<Data?>
    let visibleBadgeIds: OptionalChange<[String]>

    let userProfileWriter: UserProfileWriter

    init(
        profileGivenName: OptionalChange<OWSUserProfile.NameComponent>,
        profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>,
        profileBio: OptionalChange<String?>,
        profileBioEmoji: OptionalChange<String?>,
        profileAvatarData: OptionalAvatarChange<Data?>,
        visibleBadgeIds: OptionalChange<[String]>,
        userProfileWriter: UserProfileWriter
    ) {
        self.id = UUID()
        self.profileGivenName = profileGivenName
        self.profileFamilyName = profileFamilyName
        self.profileBio = profileBio
        self.profileBioEmoji = profileBioEmoji
        self.profileAvatarData = Self.normalizeAvatar(profileAvatarData)
        self.visibleBadgeIds = visibleBadgeIds
        self.userProfileWriter = userProfileWriter
    }

    func hasSameIdAs(_ other: PendingProfileUpdate) -> Bool {
        return self.id == other.id
    }

    private static func normalizeAvatar(_ avatarData: OptionalAvatarChange<Data?>) -> OptionalAvatarChange<Data?> {
        return avatarData.map { $0?.nilIfEmpty }
    }

    // MARK: - NSCoding

    public class var supportsSecureCoding: Bool { true }

    private enum NSCodingKeys: String {
        case id
        case profileGivenName
        case profileFamilyName
        case profileBio
        case profileBioEmoji
        case profileAvatarData
        case visibleBadgeIds
        case userProfileWriter

        var changedKey: String { rawValue + "Changed" }
        var mustReuploadKey: String { rawValue + "MustReupload" }
    }

    private static func encodeOptionalChange<T>(_ value: OptionalChange<T?>, for codingKey: NSCodingKeys, with aCoder: NSCoder) {
        switch value {
        case .noChange:
            aCoder.encode(false, forKey: codingKey.changedKey)
        case .setTo(let value):
            if let value {
                aCoder.encode(value, forKey: codingKey.rawValue)
            }
        }
    }

    private static func encodeOptionalAvatarChange<T>(_ value: OptionalAvatarChange<T?>, for codingKey: NSCodingKeys, with aCoder: NSCoder) {
        switch value {
        case .noChangeButMustReupload:
            aCoder.encode(true, forKey: codingKey.mustReuploadKey)
            fallthrough
        case .noChange:
            aCoder.encode(false, forKey: codingKey.changedKey)
        case .setTo(let value):
            if let value {
                aCoder.encode(value, forKey: codingKey.rawValue)
            }
        }
    }

    private static func encodeVisibleBadgeIds(_ value: OptionalChange<[String]>, for codingKey: NSCodingKeys, with aCoder: NSCoder) {
        switch value {
        case .noChange:
            break
        case .setTo(let value):
            aCoder.encode(value, forKey: codingKey.rawValue)
        }
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(id.uuidString, forKey: NSCodingKeys.id.rawValue)
        Self.encodeOptionalChange(profileGivenName.map { $0.stringValue.rawValue }, for: .profileGivenName, with: aCoder)
        Self.encodeOptionalChange(profileFamilyName.map { $0?.stringValue.rawValue }, for: .profileFamilyName, with: aCoder)
        Self.encodeOptionalChange(profileBio, for: .profileBio, with: aCoder)
        Self.encodeOptionalChange(profileBioEmoji, for: .profileBioEmoji, with: aCoder)
        Self.encodeOptionalAvatarChange(profileAvatarData, for: .profileAvatarData, with: aCoder)
        Self.encodeVisibleBadgeIds(visibleBadgeIds, for: .visibleBadgeIds, with: aCoder)
        aCoder.encodeCInt(Int32(userProfileWriter.rawValue), forKey: NSCodingKeys.userProfileWriter.rawValue)
    }

    private static func decodeOptionalChange<T: NSObject & NSSecureCoding>(of cls: T.Type, for codingKey: NSCodingKeys, with aDecoder: NSCoder) -> OptionalChange<T?> {
        if aDecoder.containsValue(forKey: codingKey.changedKey), !aDecoder.decodeBool(forKey: codingKey.changedKey) {
            return .noChange
        }
        return .setTo(aDecoder.decodeObject(of: cls, forKey: codingKey.rawValue) as T?)
    }

    private static func decodeOptionalAvatarChange(for codingKey: NSCodingKeys, with aDecoder: NSCoder) -> OptionalAvatarChange<Data?> {
        if aDecoder.containsValue(forKey: codingKey.changedKey), !aDecoder.decodeBool(forKey: codingKey.changedKey) {
            if aDecoder.containsValue(forKey: codingKey.mustReuploadKey), aDecoder.decodeBool(forKey: codingKey.mustReuploadKey) {
                return .noChangeButMustReupload
            }
            return .noChange
        }
        return .setTo(aDecoder.decodeObject(of: NSData.self, forKey: codingKey.rawValue) as Data?)
    }

    private static func decodeOptionalNameChange(
        for codingKey: NSCodingKeys,
        with aDecoder: NSCoder
    ) -> OptionalChange<OWSUserProfile.NameComponent?> {
        let stringChange = decodeOptionalChange(of: NSString.self, for: codingKey, with: aDecoder)
        switch stringChange {
        case .noChange:
            return .noChange
        case .setTo(.none):
            return .setTo(nil)
        case .setTo(.some(let value)):
            // We shouldn't be able to encode an invalid value. If we do, fall back to
            // `.noChange` rather than clearing it.
            guard let nameComponent = OWSUserProfile.NameComponent(truncating: value as String) else {
                return .noChange
            }
            return .setTo(nameComponent)
        }
    }

    private static func decodeRequiredNameChange(
        for codingKey: NSCodingKeys,
        with aDecoder: NSCoder
    ) -> OptionalChange<OWSUserProfile.NameComponent> {
        switch decodeOptionalNameChange(for: codingKey, with: aDecoder) {
        case .noChange:
            return .noChange
        case .setTo(.none):
            // Don't allow the value to be cleared. Fall back to `.noChange` rather
            // than throwing an error.
            return .noChange
        case .setTo(.some(let value)):
            return .setTo(value)
        }
    }

    private static func decodeVisibleBadgeIds(for codingKey: NSCodingKeys, with aDecoder: NSCoder) -> OptionalChange<[String]> {
        guard let visibleBadgeIds = aDecoder.decodeArrayOfObjects(ofClass: NSString.self, forKey: codingKey.rawValue) as [String]? else {
            return .noChange
        }
        return .setTo(visibleBadgeIds)
    }

    public required init?(coder aDecoder: NSCoder) {
        guard
            let idString = aDecoder.decodeObject(of: NSString.self, forKey: NSCodingKeys.id.rawValue) as String?,
            let id = UUID(uuidString: idString)
        else {
            owsFailDebug("Missing id")
            return nil
        }
        self.id = id
        self.profileGivenName = Self.decodeRequiredNameChange(for: .profileGivenName, with: aDecoder)
        self.profileFamilyName = Self.decodeOptionalNameChange(for: .profileFamilyName, with: aDecoder)
        self.profileBio = Self.decodeOptionalChange(of: NSString.self, for: .profileBio, with: aDecoder).map({ $0 as String? })
        self.profileBioEmoji = Self.decodeOptionalChange(of: NSString.self, for: .profileBioEmoji, with: aDecoder).map({ $0 as String? })
        self.profileAvatarData = Self.normalizeAvatar(Self.decodeOptionalAvatarChange(for: .profileAvatarData, with: aDecoder))
        self.visibleBadgeIds = Self.decodeVisibleBadgeIds(for: .visibleBadgeIds, with: aDecoder)
        if
            aDecoder.containsValue(forKey: NSCodingKeys.userProfileWriter.rawValue),
            let userProfileWriter = UserProfileWriter(rawValue: UInt(aDecoder.decodeInt32(forKey: NSCodingKeys.userProfileWriter.rawValue)))
        {
            self.userProfileWriter = userProfileWriter
        } else {
            self.userProfileWriter = .unknown
        }
    }
}

// MARK: - Avatar Downloads

extension OWSProfileManager {
    fileprivate struct AvatarDownloadKey: Hashable {
        let avatarUrlPath: String
        let profileKey: Data
    }

    public func downloadAndDecryptLocalUserAvatarIfNeeded(authedAccount: AuthedAccount) async throws {
        let oldProfile = SSKEnvironment.shared.databaseStorageRef.read { tx in OWSUserProfile.getUserProfile(for: .localUser, tx: tx) }
        guard
            let oldProfile,
            let profileKey = oldProfile.profileKey,
            let avatarUrlPath = oldProfile.avatarUrlPath,
            !avatarUrlPath.isEmpty,
            oldProfile.avatarFileName == nil
        else {
            return
        }
        let shouldRetry: Bool
        do {
            let typedProfileKey = try ProfileKey(contents: [UInt8](profileKey.keyData))
            let temporaryFileUrl = try await downloadAndDecryptAvatar(avatarUrlPath: avatarUrlPath, profileKey: typedProfileKey)
            var didConsumeFilePath = false
            defer {
                if !didConsumeFilePath { try? FileManager.default.removeItem(at: temporaryFileUrl) }
            }
            (shouldRetry, didConsumeFilePath) = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                let newProfile = OWSUserProfile.getUserProfile(for: .localUser, tx: tx)
                guard let newProfile, newProfile.avatarFileName == nil else {
                    return (false, false)
                }
                // If the URL/profileKey change, we have a new avatar to download.
                guard newProfile.profileKey == profileKey, newProfile.avatarUrlPath == avatarUrlPath else {
                    return (true, false)
                }
                let avatarFilename = try OWSUserProfile.consumeTemporaryAvatarFileUrl(.setTo(temporaryFileUrl), tx: tx)
                newProfile.update(
                    avatarFileName: avatarFilename,
                    userProfileWriter: .avatarDownload,
                    transaction: tx,
                    completion: nil
                )
                return (false, true)
            }
        }
        if shouldRetry {
            try await downloadAndDecryptLocalUserAvatarIfNeeded(authedAccount: authedAccount)
        }
    }

    public func downloadAndDecryptAvatar(avatarUrlPath: String, profileKey: ProfileKey) async throws -> URL {
        let backgroundTask = OWSBackgroundTask(label: "\(#function)")
        defer { backgroundTask.end() }

        return try await Self._downloadAndDecryptAvatar(
            avatarUrlPath: avatarUrlPath,
            profileKey: profileKey,
            remainingRetries: 3
        )
    }

    private static func _downloadAndDecryptAvatar(
        avatarUrlPath: String,
        profileKey: ProfileKey,
        remainingRetries: Int
    ) async throws -> URL {
        assert(!avatarUrlPath.isEmpty)
        do {
            Logger.info("")
            let urlSession = self.avatarUrlSession
            let response = try await urlSession.performDownload(avatarUrlPath, method: .get)
            let decryptedFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
            try decryptAvatar(at: response.downloadUrl, to: decryptedFileUrl, profileKey: profileKey)
            guard Data.ows_isValidImage(at: decryptedFileUrl, mimeType: nil) else {
                throw OWSGenericError("Couldn't validate avatar")
            }
            guard UIImage(contentsOfFile: decryptedFileUrl.path) != nil else {
                throw OWSGenericError("Couldn't decode image")
            }
            return decryptedFileUrl
        } catch where error.isNetworkFailureOrTimeout && remainingRetries > 0 {
            return try await _downloadAndDecryptAvatar(
                avatarUrlPath: avatarUrlPath,
                profileKey: profileKey,
                remainingRetries: remainingRetries - 1
            )
        }
    }

    private static func decryptAvatar(
        at encryptedFileUrl: URL,
        to decryptedFileUrl: URL,
        profileKey: ProfileKey
    ) throws {
        let readHandle = try FileHandle(forReadingFrom: encryptedFileUrl)
        defer {
            try? readHandle.close()
        }
        guard
            FileManager.default.createFile(
                atPath: decryptedFileUrl.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        else {
            throw OWSGenericError("Couldn't create temporary file")
        }
        let writeHandle = try FileHandle(forWritingTo: decryptedFileUrl)
        defer {
            try? writeHandle.close()
        }

        let concatenatedLength = Int(try readHandle.seekToEnd())
        try readHandle.seek(toOffset: 0)

        let nonceLength = Aes256GcmEncryptedData.nonceLength
        let authenticationTagLength = Aes256GcmEncryptedData.authenticationTagLength

        var remainingLength = concatenatedLength - nonceLength - authenticationTagLength
        guard remainingLength >= 0 else {
            throw OWSGenericError("ciphertext too short")
        }

        let nonceData = try readHandle.read(upToCount: nonceLength) ?? Data()

        let decryptor = try Aes256GcmDecryption(key: profileKey.serialize().asData, nonce: nonceData, associatedData: [])
        while remainingLength > 0 {
            let kBatchLimit = 32768
            var payloadData: Data = try readHandle.read(upToCount: min(remainingLength, kBatchLimit)) ?? Data()
            try decryptor.decrypt(&payloadData)
            try writeHandle.write(contentsOf: payloadData)
            remainingLength -= payloadData.count
        }

        let authenticationTag = try readHandle.read(upToCount: authenticationTagLength) ?? Data()
        guard try decryptor.verifyTag(authenticationTag) else {
            throw OWSGenericError("failed to decrypt")
        }
    }
}
