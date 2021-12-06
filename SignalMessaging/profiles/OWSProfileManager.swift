//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

public extension OWSProfileManager {

    // The main entry point for updating the local profile. It will:
    //
    // * Enqueue a service update.
    // * Attempt that service update.
    //
    // The returned promise will fail if the service can't be updated
    // (or in the unlikely fact that another error occurs) but this
    // manager will continue to retry until the update succeeds.
    class func updateLocalProfilePromise(profileGivenName: String?,
                                         profileFamilyName: String?,
                                         profileBio: String?,
                                         profileBioEmoji: String?,
                                         profileAvatarData: Data?,
                                         visibleBadgeIds: [String],
                                         unsavedRotatedProfileKey: OWSAES256Key? = nil,
                                         userProfileWriter: UserProfileWriter) -> Promise<Void> {
        assert(CurrentAppContext().isMainApp)

        return DispatchQueue.global().async(.promise) {
            return enqueueProfileUpdate(profileGivenName: profileGivenName,
                                        profileFamilyName: profileFamilyName,
                                        profileBio: profileBio,
                                        profileBioEmoji: profileBioEmoji,
                                        profileAvatarData: profileAvatarData,
                                        visibleBadgeIds: visibleBadgeIds,
                                        unsavedRotatedProfileKey: unsavedRotatedProfileKey,
                                        userProfileWriter: userProfileWriter)
        }.then(on: .main) { update in
            return self.attemptToUpdateProfileOnService(update: update)
        }.then { (_) throws -> Promise<Void> in
            guard unsavedRotatedProfileKey == nil else {
                Logger.info("Skipping local profile fetch during key rotation.")
                return Promise.value(())
            }

            guard let localAddress = TSAccountManager.shared.localAddress else {
                throw OWSAssertionError("missing local address")
            }
            return ProfileFetcherJob.fetchProfilePromise(address: localAddress, mainAppOnly: false, ignoreThrottling: true, fetchType: .default).asVoid()
        }.done(on: .global()) { () -> Void in
            Logger.verbose("Profile update did complete.")
        }
    }

    // This will re-upload the existing local profile state.
    func reuploadLocalProfilePromise(unsavedRotatedProfileKey: OWSAES256Key? = nil) -> Promise<Void> {
        Logger.info("")

        let profileGivenName: String?
        let profileFamilyName: String?
        let profileBio: String?
        let profileBioEmoji: String?
        let profileAvatarData: Data?
        let visibleBadgeIds: [String]
        let userProfileWriter: UserProfileWriter
        if let pendingUpdate = (Self.databaseStorage.read { transaction in
            return Self.currentPendingProfileUpdate(transaction: transaction)
        }) {
            profileGivenName = pendingUpdate.profileGivenName
            profileFamilyName = pendingUpdate.profileFamilyName
            profileBio = pendingUpdate.profileBio
            profileBioEmoji = pendingUpdate.profileBioEmoji
            profileAvatarData = pendingUpdate.profileAvatarData
            visibleBadgeIds = pendingUpdate.visibleBadgeIds
            userProfileWriter = pendingUpdate.userProfileWriter

            if DebugFlags.internalLogging {
                Logger.info("Re-uploading currentPendingProfileUpdate: \(profileAvatarData?.count ?? 0 > 0).")
            }
        } else {
            let profileSnapshot = localProfileSnapshot(shouldIncludeAvatar: true)
            profileGivenName = profileSnapshot.givenName
            profileFamilyName = profileSnapshot.familyName
            profileBio = profileSnapshot.bio
            profileBioEmoji = profileSnapshot.bioEmoji
            profileAvatarData = profileSnapshot.avatarData
            visibleBadgeIds = profileSnapshot.profileBadgeInfo?.filter { $0.isVisible ?? true }.map { $0.badgeId } ?? []
            userProfileWriter = .reupload

            if DebugFlags.internalLogging {
                Logger.info("Re-uploading localProfileSnapshot: \(profileAvatarData?.count ?? 0 > 0).")
            }
        }
        assert(profileGivenName != nil)
        return OWSProfileManager.updateLocalProfilePromise(profileGivenName: profileGivenName,
                                                           profileFamilyName: profileFamilyName,
                                                           profileBio: profileBio,
                                                           profileBioEmoji: profileBioEmoji,
                                                           profileAvatarData: profileAvatarData,
                                                           visibleBadgeIds: visibleBadgeIds,
                                                           unsavedRotatedProfileKey: unsavedRotatedProfileKey,
                                                           userProfileWriter: userProfileWriter)
    }

    @objc
    func allWhitelistedRegisteredAddresses(transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        var addresses = Set<SignalServiceAddress>()
        for uuid in whitelistedUUIDsStore.allKeys(transaction: transaction) {
            addresses.insert(SignalServiceAddress(uuidString: uuid))
        }
        for phoneNumber in whitelistedPhoneNumbersStore.allKeys(transaction: transaction) {
            addresses.insert(SignalServiceAddress(phoneNumber: phoneNumber))
        }

        return AnySignalRecipientFinder().signalRecipients(for: Array(addresses), transaction: transaction)
            .filter { $0.devices.count > 0 }
            .map { $0.address }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    func rotateProfileKey(
        intersectingPhoneNumbers: Set<String>,
        intersectingUUIDs: Set<String>,
        intersectingGroupIds: Set<Data>
    ) -> AnyPromise {
        return AnyPromise(rotateProfileKey(
            intersectingPhoneNumbers: intersectingPhoneNumbers,
            intersectingUUIDs: intersectingUUIDs,
            intersectingGroupIds: intersectingGroupIds
        ))
    }

    func rotateProfileKey(
        intersectingPhoneNumbers: Set<String>,
        intersectingUUIDs: Set<String>,
        intersectingGroupIds: Set<Data>
    ) -> Promise<Void> {
        guard tsAccountManager.isRegisteredPrimaryDevice else {
            return Promise(error: OWSAssertionError("tsAccountManager.isRegistered was unexpectedly false"))
        }

        Logger.info("Beginning profile key rotation.")

        // The order of operations here is very important to prevent races
        // between when we rotate our profile key and reupload our profile.
        // It's essential we avoid a case where other devices are operating
        // with a *new* profile key that we have yet to upload a profile for.

        return firstly(on: .global()) { () -> Promise<OWSAES256Key> in
            Logger.info("Reuploading profile with new profile key")

            // We re-upload our local profile with the new profile key
            // *before* we persist it. This is safe, because versioned
            // profiles allow other clients to continue using our old
            // profile key with the old version of our profile. It is
            // possible this operation will fail, in which case we will
            // try to rotate your profile key again on the next app
            // launch or blocklist change and continue to use the old
            // profile key.

            let newProfileKey = OWSAES256Key.generateRandom()
            return self.reuploadLocalProfilePromise(unsavedRotatedProfileKey: newProfileKey).map { newProfileKey }
        }.then(on: .global()) { newProfileKey -> Promise<Void> in
            guard let localAddress = self.tsAccountManager.localAddress else {
                throw OWSAssertionError("Missing local address")
            }

            Logger.info("Persisting rotated profile key and kicking off subsequent operations.")

            return self.databaseStorage.write(.promise) { transaction in
                self.setLocalProfileKey(newProfileKey,
                                        userProfileWriter: .localUser,
                                        transaction: transaction)

                // Whenever a user's profile key changes, we need to fetch a new
                // profile key credential for them.
                self.versionedProfiles.clearProfileKeyCredential(for: localAddress, transaction: transaction)

                // We schedule the updates here but process them below using processProfileKeyUpdates.
                // It's more efficient to process them after the intermediary steps are done.
                self.groupsV2.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: transaction)

                // It's absolutely essential that these values are persisted in the same transaction
                // in which we persist our new profile key, since storing them is what marks the
                // profile key rotation as "complete" (removing newly blocked users from the whitelist).
                self.whitelistedPhoneNumbersStore.removeValues(
                    forKeys: Array(intersectingPhoneNumbers),
                    transaction: transaction
                )
                self.whitelistedUUIDsStore.removeValues(
                    forKeys: Array(intersectingUUIDs),
                    transaction: transaction
                )
                self.whitelistedGroupsStore.removeValues(
                    forKeys: intersectingGroupIds.map { self.groupKey(forGroupId: $0) },
                    transaction: transaction
                )
            }
        }.then(on: .global()) { () -> Promise<Void> in
            Logger.info("Updating account attributes after profile key rotation.")
            return self.tsAccountManager.updateAccountAttributes()
        }.done(on: .global()) {
            Logger.info("Completed profile key rotation.")
            self.groupsV2.processProfileKeyUpdates()
        }
    }
}

// MARK: -

@objc
public extension OWSProfileManager {
    @available(swift, obsoleted: 1.0)
    class func updateProfileOnServiceIfNecessary() {
        updateProfileOnServiceIfNecessary()
    }

    // This will re-upload the existing local profile state.
    @available(swift, obsoleted: 1.0)
    func reuploadLocalProfilePromise() -> AnyPromise {
        return AnyPromise(reuploadLocalProfilePromise())
    }

    @available(swift, obsoleted: 1.0)
    class func updateLocalProfilePromise(profileGivenName: String?,
                                         profileFamilyName: String?,
                                         profileBio: String?,
                                         profileBioEmoji: String?,
                                         profileAvatarData: Data?,
                                         visibleBadgeIds: [String],
                                         userProfileWriter: UserProfileWriter) -> AnyPromise {
        return AnyPromise(updateLocalProfilePromise(
            profileGivenName: profileGivenName,
            profileFamilyName: profileFamilyName,
            profileBio: profileBio,
            profileBioEmoji: profileBioEmoji,
            profileAvatarData: profileAvatarData,
            visibleBadgeIds: visibleBadgeIds,
            userProfileWriter: userProfileWriter
        ))
    }

    class func updateStorageServiceIfNecessary() {
        guard CurrentAppContext().isMainApp,
              !CurrentAppContext().isRunningTests,
              tsAccountManager.isRegisteredAndReady,
              tsAccountManager.isRegisteredPrimaryDevice else {
                  return
              }

        let hasUpdated = databaseStorage.read { transaction in
            storageServiceStore.getBool(Self.hasUpdatedStorageServiceKey,
                                        defaultValue: false,
                                        transaction: transaction)
        }

        guard !hasUpdated else {
            return
        }

        if profileManager.localProfileAvatarData() != nil {
            Logger.info("Scheduling a backup.")

            // Schedule a backup.
            storageServiceManager.recordPendingLocalAccountUpdates()
        }

        databaseStorage.write { transaction in
            storageServiceStore.setBool(true,
                                        key: Self.hasUpdatedStorageServiceKey,
                                        transaction: transaction)
        }
    }

    private static let storageServiceStore = SDSKeyValueStore(collection: "OWSProfileManager.storageServiceStore")
    private static let hasUpdatedStorageServiceKey = "hasUpdatedStorageServiceKey"
}

// MARK: -

extension OWSProfileManager {

    private class var avatarUrlSession: OWSURLSession {
        return OWSSignalService.shared().urlSessionForCdn(cdnNumber: 0)
    }
    @objc
    static let settingsStore = SDSKeyValueStore(collection: "kOWSProfileManager_SettingsStore")

    // MARK: -

    public class func updateProfileOnServiceIfNecessary(retryDelay: TimeInterval = 1) {
        AssertIsOnMainThread()

        guard AppReadiness.isAppReady else {
            return
        }
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }
        guard !profileManagerImpl.isUpdatingProfileOnService else {
            // Avoid having two redundant updates in flight at the same time.
            return
        }

        let pendingUpdate = self.databaseStorage.read { transaction in
            return self.currentPendingProfileUpdate(transaction: transaction)
        }
        guard let update = pendingUpdate else {
            return
        }
        firstly {
            attemptToUpdateProfileOnService(update: update,
                                            retryDelay: retryDelay)
        }.done { _ in
            Logger.info("Update succeeded.")
        }.catch { error in
            Logger.error("Update failed: \(error)")
        }
    }

    fileprivate class func attemptToUpdateProfileOnService(update: PendingProfileUpdate,
                                                           retryDelay: TimeInterval = 1) -> Promise<Void> {
        AssertIsOnMainThread()

        Logger.verbose("")

        if !update.hasGivenName {
            Logger.info("Setting empty given name.")
        }
        if !update.hasAvatarData {
            Logger.info("Setting empty avatar.")
        }

        profileManagerImpl.isUpdatingProfileOnService = true

        // We capture the local user profile early to eliminate the
        // risk of opening a transaction within a transaction.
        let userProfile = profileManagerImpl.localUserProfile()

        let attempt = ProfileUpdateAttempt(update: update,
                                           userProfile: userProfile)
        let userProfileWriter = attempt.userProfileWriter

        let promise = firstly {
            writeProfileAvatarToDisk(attempt: attempt)
        }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
            Logger.info("Versioned profile update, avatarUrlPath: \(attempt.avatarUrlPath?.nilIfEmpty != nil), avatarFilename: \(attempt.avatarFilename?.nilIfEmpty != nil)")
            return updateProfileOnServiceVersioned(attempt: attempt)
        }.done(on: DispatchQueue.global()) { _ in
            self.databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> Void in
                guard tryToDequeueProfileUpdate(update: attempt.update, transaction: transaction) else {
                    return
                }

                if attempt.update.profileAvatarData != nil {
                    if attempt.avatarFilename == nil {
                        owsFailDebug("Missing avatarFilename.")
                    }
                    if attempt.avatarUrlPath == nil {
                        owsFailDebug("Missing avatarUrlPath.")
                    }
                }

                self.updateLocalProfile(with: attempt,
                                        userProfileWriter: userProfileWriter,
                                        transaction: transaction)
            }

            self.attemptDidComplete(retryDelay: retryDelay, didSucceed: true)
        }.recover(on: .global()) { error in
            // We retry network errors forever (with exponential backoff).
            // Other errors cause us to give up immediately.
            // Note that we only ever retry the latest profile update.
            if error.isNetworkConnectivityFailure {
                Logger.warn("Retrying after error: \(error)")
            } else {
                owsFailDebug("Error: \(error)")

                // Dequeue to avoid getting stuck in retry loop.
                self.databaseStorage.write { transaction in
                    _ = tryToDequeueProfileUpdate(update: attempt.update, transaction: transaction)
                }
            }
            self.attemptDidComplete(retryDelay: retryDelay, didSucceed: false)

            // We don't actually want to recover; in this block we
            // handle the business logic consequences of the error,
            // but we re-throw so that the UI can distinguish
            // success and failure.
            throw error
        }

        return promise
    }

    private class func attemptDidComplete(retryDelay: TimeInterval, didSucceed: Bool) {
        // We use a "self-only" contact sync to indicate to desktop
        // that we've changed our profile and that it should do a
        // profile fetch for "self".
        //
        // NOTE: We also inform the desktop in the failure case,
        //       since that _may have_ affected service state.
        if self.tsAccountManager.isRegisteredPrimaryDevice {
            firstly {
                self.syncManager.syncLocalContact()
            }.catch { error in
                Logger.warn("Error: \(error)")
            }
        }

        // Notify all our devices that the profile has changed.
        // Older linked devices may not handle this message.
        self.syncManager.sendFetchLatestProfileSyncMessage()

        DispatchQueue.main.async {
            // Clear this flag immediately.
            self.profileManagerImpl.isUpdatingProfileOnService = false

            // There may be another update enqueued that we should kick off.
            // Or we may need to retry.
            if didSucceed {
                self.updateProfileOnServiceIfNecessary()
            } else {
                // We don't want to get in a retry loop, so we use exponential backoff
                // in the failure case.
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                    self.updateProfileOnServiceIfNecessary(retryDelay: (retryDelay + 1) * 2)
                })
            }
        }
    }

    private class func writeProfileAvatarToDisk(attempt: ProfileUpdateAttempt) -> Promise<Void> {
        guard let profileAvatarData = attempt.update.profileAvatarData else {
            return Promise.value(())
        }
        let (promise, future) = Promise<Void>.pending()
        DispatchQueue.global().async {
            self.profileManagerImpl.writeAvatarToDisk(with: profileAvatarData,
                                                      success: { avatarFilename in
                                                        attempt.avatarFilename = avatarFilename
                                                        future.resolve()
                                                      }, failure: { (error) in
                                                        future.reject(error)
                                                      })
        }
        return promise
    }

    private class func updateProfileOnServiceVersioned(attempt: ProfileUpdateAttempt) -> Promise<Void> {
        Logger.info("avatar?: \(attempt.update.profileAvatarData != nil), " +
                        "profileGivenName?: \(attempt.update.profileGivenName != nil), " +
                        "profileFamilyName?: \(attempt.update.profileFamilyName != nil), " +
                        "profileBio?: \(attempt.update.profileBio != nil), " +
                        "profileBioEmoji?: \(attempt.update.profileBioEmoji != nil) " +
                        "visibleBadges?: \(attempt.update.visibleBadgeIds.count).")
        return firstly(on: .global()) {
            Self.versionedProfilesImpl.updateProfilePromise(profileGivenName: attempt.update.profileGivenName,
                                                            profileFamilyName: attempt.update.profileFamilyName,
                                                            profileBio: attempt.update.profileBio,
                                                            profileBioEmoji: attempt.update.profileBioEmoji,
                                                            profileAvatarData: attempt.update.profileAvatarData,
                                                            visibleBadgeIds: attempt.update.visibleBadgeIds,
                                                            unsavedRotatedProfileKey: attempt.update.unsavedRotatedProfileKey)
        }.map(on: .global()) { versionedUpdate in
            attempt.avatarUrlPath = versionedUpdate.avatarUrlPath
        }
    }

    private class func updateLocalProfile(with attempt: ProfileUpdateAttempt,
                                          userProfileWriter: UserProfileWriter,
                                          transaction: SDSAnyWriteTransaction) {
        Logger.verbose("profile givenName: \(String(describing: attempt.update.profileGivenName)), familyName: \(String(describing: attempt.update.profileFamilyName)), avatarFilename: \(String(describing: attempt.avatarFilename))")

        attempt.userProfile.update(givenName: attempt.update.profileGivenName,
                                   familyName: attempt.update.profileFamilyName,
                                   avatarUrlPath: attempt.avatarUrlPath,
                                   avatarFileName: attempt.avatarFilename,
                                   userProfileWriter: userProfileWriter,
                                   transaction: transaction,
                                   completion: nil)
    }

    // MARK: - Update Queue

    private static let kPendingProfileUpdateKey = "kPendingProfileUpdateKey"

    private class func enqueueProfileUpdate(profileGivenName: String?,
                                            profileFamilyName: String?,
                                            profileBio: String?,
                                            profileBioEmoji: String?,
                                            profileAvatarData: Data?,
                                            visibleBadgeIds: [String],
                                            unsavedRotatedProfileKey: OWSAES256Key?,
                                            userProfileWriter: UserProfileWriter) -> PendingProfileUpdate {
        Logger.verbose("")

        // Note that this might overwrite a pending profile update.
        // That's desirable.  We only ever want to retain the
        // latest changes.
        let update = PendingProfileUpdate(profileGivenName: profileGivenName,
                                          profileFamilyName: profileFamilyName,
                                          profileBio: profileBio,
                                          profileBioEmoji: profileBioEmoji,
                                          profileAvatarData: profileAvatarData,
                                          visibleBadgeIds: visibleBadgeIds,
                                          unsavedRotatedProfileKey: unsavedRotatedProfileKey,
                                          userProfileWriter: userProfileWriter)
        databaseStorage.write { transaction in
            self.settingsStore.setObject(update, key: kPendingProfileUpdateKey, transaction: transaction)
        }
        return update
    }

    private class func currentPendingProfileUpdate(transaction: SDSAnyReadTransaction) -> PendingProfileUpdate? {
        guard let value = settingsStore.getObject(forKey: kPendingProfileUpdateKey, transaction: transaction) else {
            return nil
        }
        guard let update = value as? PendingProfileUpdate else {
            owsFailDebug("Invalid value.")
            return nil
        }
        return update
    }

    private class func isCurrentPendingProfileUpdate(update: PendingProfileUpdate, transaction: SDSAnyReadTransaction) -> Bool {
        guard let currentUpdate = currentPendingProfileUpdate(transaction: transaction) else {
            return false
        }
        return update.hasSameIdAs(currentUpdate)
    }

    private class func tryToDequeueProfileUpdate(update: PendingProfileUpdate, transaction: SDSAnyWriteTransaction) -> Bool {
        Logger.verbose("")

        guard self.isCurrentPendingProfileUpdate(update: update, transaction: transaction) else {
            Logger.warn("Ignoring stale update completion.")
            return false
        }
        self.settingsStore.removeValue(forKey: kPendingProfileUpdateKey, transaction: transaction)
        return true
    }
}

// MARK: -

class PendingProfileUpdate: NSObject, NSCoding {
    let id: UUID

    // If nil, we are clearing the profile given name.
    let profileGivenName: String?

    // If nil, we are clearing the profile family name.
    let profileFamilyName: String?

    let profileBio: String?

    let profileBioEmoji: String?

    // If nil, we are clearing the profile avatar.
    let profileAvatarData: Data?

    let visibleBadgeIds: [String]

    let unsavedRotatedProfileKey: OWSAES256Key?

    var hasGivenName: Bool {
        guard let givenName = profileGivenName else {
            return false
        }
        return !givenName.isEmpty
    }

    var hasAvatarData: Bool {
        guard let avatarData = profileAvatarData else {
            return false
        }
        return !avatarData.isEmpty
    }

    let userProfileWriter: UserProfileWriter

    init(profileGivenName: String?,
         profileFamilyName: String?,
         profileBio: String?,
         profileBioEmoji: String?,
         profileAvatarData: Data?,
         visibleBadgeIds: [String],
         unsavedRotatedProfileKey: OWSAES256Key?,
         userProfileWriter: UserProfileWriter) {

        self.id = UUID()
        self.profileGivenName = profileGivenName
        self.profileFamilyName = profileFamilyName
        self.profileBio = profileBio
        self.profileBioEmoji = profileBioEmoji
        self.profileAvatarData = profileAvatarData
        self.visibleBadgeIds = visibleBadgeIds
        self.unsavedRotatedProfileKey = unsavedRotatedProfileKey
        self.userProfileWriter = userProfileWriter
    }

    func hasSameIdAs(_ other: PendingProfileUpdate) -> Bool {
        return self.id == other.id
    }

    // MARK: - NSCoding

    @objc
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(id.uuidString, forKey: "id")
        aCoder.encode(profileGivenName, forKey: "profileGivenName")
        aCoder.encode(profileFamilyName, forKey: "profileFamilyName")
        aCoder.encode(profileBio, forKey: "profileBio")
        aCoder.encode(profileBioEmoji, forKey: "profileBioEmoji")
        aCoder.encode(profileAvatarData, forKey: "profileAvatarData")
        aCoder.encode(visibleBadgeIds, forKey: "visibleBadgeIds")
        aCoder.encode(unsavedRotatedProfileKey, forKey: "unsavedRotatedProfileKey")
        aCoder.encodeCInt(Int32(userProfileWriter.rawValue), forKey: "userProfileWriter")
    }

    @objc
    public required init?(coder aDecoder: NSCoder) {
        guard let idString = aDecoder.decodeObject(forKey: "id") as? String,
              let id = UUID(uuidString: idString) else {
            owsFailDebug("Missing id")
            return nil
        }
        self.id = id
        self.profileGivenName = aDecoder.decodeObject(forKey: "profileGivenName") as? String
        self.profileFamilyName = aDecoder.decodeObject(forKey: "profileFamilyName") as? String
        self.profileBio = aDecoder.decodeObject(forKey: "profileBio") as? String
        self.profileBioEmoji = aDecoder.decodeObject(forKey: "profileBioEmoji") as? String
        self.profileAvatarData = aDecoder.decodeObject(forKey: "profileAvatarData") as? Data
        self.visibleBadgeIds = (aDecoder.decodeObject(forKey: "visibleBadgeIds") as? [String]) ?? []
        self.unsavedRotatedProfileKey = aDecoder.decodeObject(forKey: "unsavedRotatedProfileKey") as? OWSAES256Key
        if aDecoder.containsValue(forKey: "userProfileWriter"),
           let userProfileWriter = UserProfileWriter(rawValue: UInt(aDecoder.decodeInt32(forKey: "userProfileWriter"))) {
            self.userProfileWriter = userProfileWriter
        } else {
            self.userProfileWriter = .unknown
        }
    }
}

// MARK: -

private class ProfileUpdateAttempt {
    let update: PendingProfileUpdate

    let userProfile: OWSUserProfile

    // These properties are populated during the update process.
    var avatarFilename: String?
    var avatarUrlPath: String?

    var userProfileWriter: UserProfileWriter { update.userProfileWriter }

    init(update: PendingProfileUpdate, userProfile: OWSUserProfile) {
        self.update = update
        self.userProfile = userProfile
    }
}

// MARK: - Avatar Downloads

public extension OWSProfileManager {

    private struct CacheKey: Hashable {
        let avatarUrlPath: String
        let profileKey: Data
    }

    private static let serialQueue = DispatchQueue(label: "ProfileManager.serialQueue")

    private static var avatarDownloadCache = [CacheKey: Promise<Data>]()

    @objc
    class func avatarDownloadAndDecryptPromiseObjc(profileAddress: SignalServiceAddress,
                                                   avatarUrlPath: String,
                                                   profileKey: OWSAES256Key) -> AnyPromise {
        return AnyPromise(avatarDownloadAndDecryptPromise(profileAddress: profileAddress,
                                                          avatarUrlPath: avatarUrlPath,
                                                          profileKey: profileKey))
    }

    private class func avatarDownloadAndDecryptPromise(profileAddress: SignalServiceAddress,
                                                       avatarUrlPath: String,
                                                       profileKey: OWSAES256Key) -> Promise<Data> {
        let cacheKey = CacheKey(avatarUrlPath: avatarUrlPath, profileKey: profileKey.keyData)
        return serialQueue.sync { () -> Promise<Data> in
            if let cachedPromise = avatarDownloadCache[cacheKey] {
                return cachedPromise
            }
            let promise = avatarDownloadAndDecryptPromise(profileAddress: profileAddress,
                                                          avatarUrlPath: avatarUrlPath,
                                                          profileKey: profileKey,
                                                          remainingRetries: 3)
            avatarDownloadCache[cacheKey] = promise
            _ = promise.ensure(on: OWSProfileManager.serialQueue) {
                guard avatarDownloadCache[cacheKey] != nil else {
                    owsFailDebug("Missing cached promise.")
                    return
                }
                avatarDownloadCache.removeValue(forKey: cacheKey)
            }
            return promise
        }
    }

    private class func avatarDownloadAndDecryptPromise(profileAddress: SignalServiceAddress,
                                                       avatarUrlPath: String,
                                                       profileKey: OWSAES256Key,
                                                       remainingRetries: UInt) -> Promise<Data> {
        assert(!avatarUrlPath.isEmpty)

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)")

        return firstly(on: .global()) { () throws -> Promise<OWSUrlDownloadResponse> in
            Logger.verbose("downloading profile avatar: \(profileAddress)")
            let urlSession = self.avatarUrlSession
            return urlSession.downloadTaskPromise(avatarUrlPath,
                                                  method: .get,
                                                  progress: { (_, progress) in
                Logger.verbose("Downloading avatar for \(profileAddress) \(progress.fractionCompleted)")
            })
        }.map(on: .global()) { (response: OWSUrlDownloadResponse) -> Data in
            do {
                return try Data(contentsOf: response.downloadUrl)
            } catch {
                owsFailDebug("Could not load data failed: \(error)")
                // Fail immediately; do not retry.
                throw SSKUnretryableError.couldNotLoadFileData
            }
        }.recover(on: .global()) { (error: Error) -> Promise<Data> in
            throw error
        }.map(on: .global()) { (encryptedData: Data) -> Data in
            guard let decryptedData = OWSUserProfile.decrypt(profileData: encryptedData,
                                                             profileKey: profileKey) else {
                throw OWSGenericError("Could not decrypt profile avatar.")
            }
            return decryptedData
        }.recover { error -> Promise<Data> in
            if error.isNetworkFailureOrTimeout,
               remainingRetries > 0 {
                // Retry
                return self.avatarDownloadAndDecryptPromise(profileAddress: profileAddress,
                                                            avatarUrlPath: avatarUrlPath,
                                                            profileKey: profileKey,
                                                            remainingRetries: remainingRetries - 1)
            } else {
                throw error
            }
        }.ensure {
            assert(backgroundTask != nil)
            backgroundTask = nil
        }
    }
}

// MARK: -

extension OWSUserProfile {
    #if TESTABLE_BUILD
    func logDates(prefix: String) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        var lastFetchDateString = "nil"
        if let lastFetchDate = lastFetchDate {
            lastFetchDateString = formatter.string(from: lastFetchDate)
        }
        var lastMessagingDateString = "nil"
        if let lastMessagingDate = lastMessagingDate {
            lastMessagingDateString = formatter.string(from: lastMessagingDate)
        }
        Logger.verbose("\(prefix): \(address), lastFetchDate: \(lastFetchDateString), lastMessagingDate: \(lastMessagingDateString).")
    }
    #endif
}
