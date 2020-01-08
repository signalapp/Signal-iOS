//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

public extension OWSProfileManager {

    // The main entry point for updating the local profile. It will:
    //
    // * Update local state optimistically.
    // * Enqueue a service update.
    // * Attempt that service update.
    //
    // The returned promise will fail if the service can't be updated
    // (or in the unlikely fact that another error occurs) but this
    // manager will continue to retry until the update succeeds.
    class func updateLocalProfilePromise(profileName: String?, profileAvatarData: Data?) -> Promise<Void> {
        return DispatchQueue.global().async(.promise) {
            return enqueueProfileUpdate(profileName: profileName, profileAvatarData: profileAvatarData)
            }.then { update in
                return self.attemptToUpdateProfileOnService(update: update)
            }.done(on: .global()) { () -> Void in
                Logger.verbose("Profile update did complete.")
        }
    }
}

// MARK: -

@objc
public extension OWSProfileManager {
    // See OWSProfileManager.updateProfilePromise().
    class func updateLocalProfilePromiseObj(profileName: String?, profileAvatarData: Data?) -> AnyPromise {
        return AnyPromise(updateLocalProfilePromise(profileName: profileName, profileAvatarData: profileAvatarData))
    }

    class func updateProfileOnServiceIfNecessaryObjc() {
        updateProfileOnServiceIfNecessary()
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
        return TSAccountManager.sharedInstance()
    }

    private class var syncManager: SyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    // MARK: -

    @objc
    static let settingsStore = SDSKeyValueStore(collection: "kOWSProfileManager_SettingsStore")

    // MARK: -

    public class func updateProfileOnServiceIfNecessary(retryDelay: TimeInterval = 1) {
        AssertIsOnMainThread()

        guard AppReadiness.isAppReady() else {
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
        attemptToUpdateProfileOnService(update: update,
                                        retryDelay: retryDelay)
            .done { _ in
                Logger.info("Update succeeded.")
            }.catch { error in
                Logger.error("Update failed: \(error)")
            }.retainUntilComplete()
    }

    fileprivate class func attemptToUpdateProfileOnService(update: PendingProfileUpdate,
                                                           retryDelay: TimeInterval = 1) -> Promise<Void> {
        AssertIsOnMainThread()

        Logger.verbose("")

        self.profileManager.isUpdatingProfileOnService = true

        // We capture the local user profile early to eliminate the
        // risk of opening a transaction within a transaction.
        let userProfile = self.profileManager.localUserProfile()

        let attempt = ProfileUpdateAttempt(update: update,
                                           userProfile: userProfile)

        let promise = writeProfileAvatarToDisk(attempt: attempt)
            .then(on: DispatchQueue.global()) { () -> Promise<Void> in
                // Optimistically update local profile state.
                databaseStorage.write { transaction in
                    self.updateLocalProfile(with: attempt, transaction: transaction)
                }

                if FeatureFlags.versionedProfiledUpdate {
                    return updateProfileOnServiceVersioned(attempt: attempt)
                } else {
                    return updateProfileOnServiceUnversioned(attempt: attempt)
                }
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
                if IsNSErrorNetworkFailure(error) {
                    owsFailDebug("Retrying after error: \(error)")
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
            self.syncManager.syncLocalContact().retainUntilComplete()
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

    private class func updateProfileOnServiceUnversioned(attempt: ProfileUpdateAttempt) -> Promise<Void> {
        return updateProfileNameOnServiceUnversioned(attempt: attempt)
            .then { _ in
                return updateProfileAvatarOnServiceUnversioned(attempt: attempt)
        }
    }

    private class func updateProfileNameOnServiceUnversioned(attempt: ProfileUpdateAttempt) -> Promise<Void> {
        let (promise, resolver) = Promise<Void>.pending()
        DispatchQueue.global().async {
            self.profileManager.updateService(unversionedProfileName: attempt.update.profileName,
                                              success: {
                                                resolver.fulfill(())
            }, failure: { error in
                resolver.reject(error)
            })
        }
        return promise
    }

    private class func updateProfileAvatarOnServiceUnversioned(attempt: ProfileUpdateAttempt) -> Promise<Void> {
        let (promise, resolver) = Promise<Void>.pending()
        DispatchQueue.global().async {
            self.profileManager.updateService(unversionedProfileAvatarData: attempt.update.profileAvatarData,
                                              success: { avatarUrlPath in
                                                attempt.avatarUrlPath = avatarUrlPath

                                                resolver.fulfill(())
            }, failure: { error in
                resolver.reject(error)
            })
        }
        return promise
    }

    private class func updateProfileOnServiceVersioned(attempt: ProfileUpdateAttempt) -> Promise<Void> {
        return VersionedProfiles.updateProfilePromise(profileName: attempt.update.profileName, profileAvatarData: attempt.update.profileAvatarData)
            .map(on: .global()) { versionedUpdate in
                attempt.avatarUrlPath = versionedUpdate.avatarUrlPath
        }
    }

    private class func updateLocalProfile(with attempt: ProfileUpdateAttempt,
                                          transaction: SDSAnyWriteTransaction) {
        Logger.verbose("profileName: \(attempt.update.profileName), avatarFilename: \(attempt.avatarFilename)")

        attempt.userProfile.update(profileName: attempt.update.profileName,
                                   avatarUrlPath: nil,
                                   avatarFileName: attempt.avatarFilename,
                                   transaction: transaction,
                                   completion: nil)
    }

    // MARK: - Update Queue

    private static let kPendingProfileUpdateKey = "kPendingProfileUpdateKey"

    private class func enqueueProfileUpdate(profileName: String?, profileAvatarData: Data?) -> PendingProfileUpdate {
        Logger.verbose("")

        // Note that this might overwrite a pending profile update.
        // That's desirable.  We only ever want to retain the
        // latest changes.
        let update = PendingProfileUpdate(profileName: profileName, profileAvatarData: profileAvatarData)
        databaseStorage.write { transaction in
            self.settingsStore.setObject(update, key: kPendingProfileUpdateKey, transaction: transaction)
        }
        return update
    }

    private class func currentPendingProfileUpdate(transaction: SDSAnyReadTransaction) -> PendingProfileUpdate? {
        guard let value = settingsStore.getObject(kPendingProfileUpdateKey, transaction: transaction) else {
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
    // This property is optional so that MTLModel can populate it after initialization.
    // It should always be set in practice.
    let id: UUID

    // If nil, we are clearing the profile name.
    let profileName: String?

    // If nil, we are clearing the profile avatar.
    let profileAvatarData: Data?

    init(profileName: String?, profileAvatarData: Data?) {
        self.id = UUID()
        self.profileName = profileName
        self.profileAvatarData = profileAvatarData
    }

    func hasSameIdAs(_ other: PendingProfileUpdate) -> Bool {
        return self.id == other.id
    }

    // MARK: - NSCoding

    @objc
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(id.uuidString, forKey: "id")
        aCoder.encode(profileName, forKey: "profileName")
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
        self.profileName = aDecoder.decodeObject(forKey: "profileName") as? String
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
