//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

public extension OWSProfileManager {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    // MARK: -

    @objc
    static let settingsStore = SDSKeyValueStore(collection: "kOWSProfileManager_SettingsStore")

    // MARK: -

    class func updateProfilePromise(profileName: String?, profileAvatarData: Data?) -> Promise<Void> {

        return DispatchQueue.global().async(.promise) {
            let update = enqueueProfileUpdate(profileName: profileName, profileAvatarData: profileAvatarData)
            return update
        }.then(on: .global()) { update in
            return self.updateProfileOnService(update: update)
        }.done(on: .global()) { (_: PendingProfileUpdate) -> Void in
            Logger.verbose("Profile update did complete.")
        }
    }

    internal class func updateProfileOnService(update: PendingProfileUpdate) -> Promise<PendingProfileUpdate> {
        self.profileManager.isUpdatingProfileOnService = true

        if FeatureFlags.versionedProfiledUpdate {
            return updateProfileOnServiceVersioned(update: update)
        } else {
            return updateProfileOnServiceUnversioned(update: update)
        }
    }

    internal class func updateProfileOnServiceVersioned(update: PendingProfileUpdate) -> Promise<PendingProfileUpdate> {
        return VersionedProfiles.updateProfilePromise(profileName: update.profileName, profileAvatarData: update.profileAvatarData)
            .map(on: .global()) { versionedUpdate in
                self.tryToCompleteProfileUpdate(update: update,
                                                avatarUrlPath: versionedUpdate.avatarUrlPath)
                return update
        }
    }

    private class func tryToCompleteProfileUpdate(update: PendingProfileUpdate,
                                                  avatarUrlPath: String?) {
        databaseStorage.write { transaction in
            guard tryToDequeueProfileUpdate(update: update, transaction: transaction) else {
                return
            }

            if update.profileAvatarData != nil && avatarUrlPath == nil {
                owsFailDebug("Missing avatarUrlPath.")
            }

            self.profileManager.isUpdatingProfileOnService = false

            self.profileManager.profileUpdateDidComplete(profileName: update.profileName,
                                                         profileAvatarData: update.profileAvatarData,
                                                         avatarUrlPath: avatarUrlPath,
                                                         transaction: transaction)
        }
    }

    // MARK: - Update Queue

    private static let kPendingProfileUpdateKey = "kPendingProfileUpdateKey"

    private class func enqueueProfileUpdate(profileName: String?, profileAvatarData: Data?) -> PendingProfileUpdate {
        let update = PendingProfileUpdate(profileName: profileName, profileAvatarData: profileAvatarData)
        databaseStorage.write { transaction in
            self.settingsStore.setObject(update, key: kPendingProfileUpdateKey, transaction: transaction)

            // Optimistically update local profile state.
            self.profileManager.profileUpdateWasEnqueued(profileName: profileName, profileAvatarData: profileAvatarData, transaction: transaction)
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
        guard self.isCurrentPendingProfileUpdate(update: update, transaction: transaction) else {
            Logger.warn("Ignoring stale update completion.")
            return false
        }
        self.settingsStore.removeValue(forKey: kPendingProfileUpdateKey, transaction: transaction)
        return true
    }
}

// MARK: -

@objc
public extension OWSProfileManager {
    class func updateProfilePromiseObj(profileName: String?, profileAvatarData: Data?) -> AnyPromise {
        return AnyPromise(updateProfilePromise(profileName: profileName, profileAvatarData: profileAvatarData))
    }
}

// MARK: -

@objc
class PendingProfileUpdate: MTLModel {
    @objc
    var id: UUID?

    @objc
    var profileName: String?

    @objc
    var profileAvatarData: Data?

    @objc
    init(profileName: String?, profileAvatarData: Data?) {
        self.id = UUID()
        self.profileName = profileName
        self.profileAvatarData = profileAvatarData
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary: [String: Any]!) throws {
        try super.init(dictionary: dictionary)
    }

    func hasSameIdAs(_ other: PendingProfileUpdate) -> Bool {
        guard let thisId = id else {
            owsFailDebug("Missing id.")
            return false
        }
        guard let otherId = other.id else {
            owsFailDebug("Missing id.")
            return false
        }
        return thisId == otherId
    }
}
