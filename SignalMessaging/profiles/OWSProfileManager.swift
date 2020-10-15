//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

public extension OWSProfileManager {

    // MARK: - Dependencies

    private class var versionedProfiles: VersionedProfilesSwift {
        return SSKEnvironment.shared.versionedProfiles as! VersionedProfilesSwift
    }

    // MARK: -

    // The main entry point for updating the local profile. It will:
    //
    // * Update local state optimistically.
    // * Enqueue a service update.
    // * Attempt that service update.
    //
    // The returned promise will fail if the service can't be updated
    // (or in the unlikely fact that another error occurs) but this
    // manager will continue to retry until the update succeeds.
    class func updateLocalProfilePromise(profileGivenName: String?, profileFamilyName: String?, profileAvatarData: Data?) -> Promise<Void> {
        assert(CurrentAppContext().isMainApp)

        return DispatchQueue.global().async(.promise) {
            return enqueueProfileUpdate(profileGivenName: profileGivenName, profileFamilyName: profileFamilyName, profileAvatarData: profileAvatarData)
        }.then { update in
            return self.attemptToUpdateProfileOnService(update: update)
        }.then { (_) throws -> Promise<Void> in
            guard let localAddress = TSAccountManager.shared().localAddress else {
                throw OWSAssertionError("missing local address")
            }
            return ProfileFetcherJob.fetchProfilePromise(address: localAddress, mainAppOnly: false, ignoreThrottling: true, fetchType: .default).asVoid()
        }.done(on: .global()) { () -> Void in
            Logger.verbose("Profile update did complete.")
        }
    }

    // This will re-upload the existing local profile state.
    func reuploadLocalProfilePromise() -> Promise<Void> {
        Logger.info("")

        let profileGivenName: String?
        let profileFamilyName: String?
        let profileAvatarData: Data?
        if let pendingUpdate = (Self.databaseStorage.read { transaction in
            return Self.currentPendingProfileUpdate(transaction: transaction)
        }) {
            profileGivenName = pendingUpdate.profileGivenName
            profileFamilyName = pendingUpdate.profileFamilyName
            profileAvatarData = pendingUpdate.profileAvatarData
        } else {
            profileGivenName = localGivenName()
            profileFamilyName = localFamilyName()
            profileAvatarData = localProfileAvatarData()
        }
        assert(profileGivenName != nil)
        return OWSProfileManager.updateLocalProfilePromise(profileGivenName: profileGivenName,
                                                           profileFamilyName: profileFamilyName,
                                                           profileAvatarData: profileAvatarData)
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
}

// MARK: -

@objc
public extension OWSProfileManager {
    // See OWSProfileManager.updateProfilePromise().
    class func updateLocalProfilePromiseObj(profileGivenName: String?, profileFamilyName: String?, profileAvatarData: Data?) -> AnyPromise {
        return AnyPromise(updateLocalProfilePromise(profileGivenName: profileGivenName, profileFamilyName: profileFamilyName, profileAvatarData: profileAvatarData))
    }

    class func updateProfileOnServiceIfNecessaryObjc() {
        updateProfileOnServiceIfNecessary()
    }

    // This will re-upload the existing local profile state.
    func reuploadLocalProfilePromiseObjc() -> AnyPromise {
        return AnyPromise(reuploadLocalProfilePromise())
    }
}

// MARK: -

extension OWSProfileManager {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private class var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private class var syncManager: SyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    private class var avatarUrlSession: OWSURLSession {
        return OWSSignalService.shared().urlSessionForCdn(cdnNumber: 0)
    }

    // MARK: -

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
        guard !profileManager.isUpdatingProfileOnService else {
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

        self.profileManager.isUpdatingProfileOnService = true

        // We capture the local user profile early to eliminate the
        // risk of opening a transaction within a transaction.
        let userProfile = self.profileManager.localUserProfile()

        let attempt = ProfileUpdateAttempt(update: update,
                                           userProfile: userProfile)

        let promise = firstly {
            writeProfileAvatarToDisk(attempt: attempt)
        }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
            // Optimistically update local profile state.
            databaseStorage.write { transaction in
                self.updateLocalProfile(with: attempt, transaction: transaction)
            }

            Logger.info("Versioned profile update.")
            return updateProfileOnServiceVersioned(attempt: attempt)
        }.done(on: DispatchQueue.global()) { _ in
            _ = self.databaseStorage.write { (transaction: SDSAnyWriteTransaction) -> Void in
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

                self.updateLocalProfile(with: attempt, transaction: transaction)
            }

            self.attemptDidComplete(retryDelay: retryDelay, didSucceed: true)
        }.recover(on: .global()) { error in
            // We retry network errors forever (with exponential backoff).
            // Other errors cause us to give up immediately.
            // Note that we only ever retry the latest profile update.
            if IsNetworkConnectivityFailure(error) {
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
            self.profileManager.isUpdatingProfileOnService = false

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
        let (promise, resolver) = Promise<Void>.pending()
        DispatchQueue.global().async {
            self.profileManager.writeAvatarToDisk(with: profileAvatarData,
                                                  success: { avatarFilename in
                                                    attempt.avatarFilename = avatarFilename
                                                    resolver.fulfill(())
            }, failure: { (error) in
                resolver.reject(error)
            })
        }
        return promise
    }

    private class func updateProfileOnServiceVersioned(attempt: ProfileUpdateAttempt) -> Promise<Void> {
        Logger.info("avatar?: \(attempt.update.profileAvatarData != nil), " +
            "profileGivenName?: \(attempt.update.profileGivenName != nil), " +
            "profileFamilyName?: \(attempt.update.profileFamilyName != nil).")
        return firstly(on: .global()) {
            versionedProfiles.updateProfilePromise(profileGivenName: attempt.update.profileGivenName,
                                                   profileFamilyName: attempt.update.profileFamilyName,
                                                   profileAvatarData: attempt.update.profileAvatarData)
        }.map(on: .global()) { versionedUpdate in
            attempt.avatarUrlPath = versionedUpdate.avatarUrlPath
        }
    }

    private class func updateLocalProfile(with attempt: ProfileUpdateAttempt,
                                          transaction: SDSAnyWriteTransaction) {
        Logger.verbose("profile givenName: \(String(describing: attempt.update.profileGivenName)), familyName: \(String(describing: attempt.update.profileFamilyName)), avatarFilename: \(String(describing: attempt.avatarFilename))")

        attempt.userProfile.updateWith(givenName: attempt.update.profileGivenName,
                                       familyName: attempt.update.profileFamilyName,
                                       avatarUrlPath: attempt.avatarUrlPath,
                                       avatarFileName: attempt.avatarFilename,
                                       transaction: transaction,
                                       completion: nil)
    }

    // MARK: - Update Queue

    private static let kPendingProfileUpdateKey = "kPendingProfileUpdateKey"

    private class func enqueueProfileUpdate(profileGivenName: String?, profileFamilyName: String?, profileAvatarData: Data?) -> PendingProfileUpdate {
        Logger.verbose("")

        // Note that this might overwrite a pending profile update.
        // That's desirable.  We only ever want to retain the
        // latest changes.
        let update = PendingProfileUpdate(profileGivenName: profileGivenName, profileFamilyName: profileFamilyName, profileAvatarData: profileAvatarData)
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

    // If nil, we are clearing the profile avatar.
    let profileAvatarData: Data?

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

    init(profileGivenName: String?, profileFamilyName: String?, profileAvatarData: Data?) {
        self.id = UUID()
        self.profileGivenName = profileGivenName
        self.profileFamilyName = profileFamilyName
        self.profileAvatarData = profileAvatarData
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
        aCoder.encode(profileAvatarData, forKey: "profileAvatarData")
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
        self.profileAvatarData = aDecoder.decodeObject(forKey: "profileAvatarData") as? Data
    }
}

// MARK: -

private class ProfileUpdateAttempt {
    let update: PendingProfileUpdate

    let userProfile: OWSUserProfile

    // These properties are populated during the update process.
    var avatarFilename: String?
    var avatarUrlPath: String?

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
            _ = promise.ensure(on: .global()) {
                serialQueue.sync {
                    guard avatarDownloadCache[cacheKey] != nil else {
                        owsFailDebug("Missing cached promise.")
                        return
                    }
                    avatarDownloadCache.removeValue(forKey: cacheKey)
                }
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
            return urlSession.urlDownloadTaskPromise(avatarUrlPath,
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
                throw error.asUnretryableError
            }
        }.recover(on: .global()) { (error: Error) -> Promise<Data> in
            throw error.withDefaultRetry
        }.map(on: .global()) { (encryptedData: Data) -> Data in
            guard let decryptedData = OWSUserProfile.decrypt(profileData: encryptedData,
                                                             profileKey: profileKey) else {
                throw OWSGenericError("Could not decrypt profile avatar.").asUnretryableError
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
