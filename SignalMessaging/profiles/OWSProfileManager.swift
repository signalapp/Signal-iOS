//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

class OWSProfileManagerSwiftValues {
    fileprivate let pendingUpdateRequests = AtomicValue<[OWSProfileManager.ProfileUpdateRequest]>([], lock: AtomicLock())
}

extension OWSProfileManager: ProfileManager {
    public func fullNames(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [String?] {
        return userProfilesRefinery(for: addresses, tx: tx).values.map { $0?.fullName }
    }

    public func fetchLocalUsersProfile(mainAppOnly: Bool, authedAccount: AuthedAccount) -> Promise<FetchedProfile> {
        do {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            return ProfileFetcherJob.fetchProfilePromise(
                serviceId: try tsAccountManager.localAciWithMaybeSneakyTransaction(authedAccount: authedAccount),
                mainAppOnly: mainAppOnly,
                ignoreThrottling: true,
                authedAccount: authedAccount
            )
        } catch {
            return Promise(error: error)
        }
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
        profileGivenName: String?,
        profileFamilyName: String?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarData: Data?,
        visibleBadgeIds: [String],
        unsavedRotatedProfileKey: OWSAES256Key?,
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
            unsavedRotatedProfileKey: unsavedRotatedProfileKey,
            userProfileWriter: userProfileWriter,
            tx: tx
        )

        let (promise, future) = Promise<Void>.pending()
        swiftValues.pendingUpdateRequests.update {
            $0.append(ProfileUpdateRequest(requestId: update.id, authedAccount: authedAccount, future: future))
        }
        tx.addAsyncCompletionOnMain {
            self._updateProfileOnServiceIfNecessary()
        }
        return promise
    }

    // This will re-upload the existing local profile state.
    public func reuploadLocalProfileWithSneakyTransaction(
        unsavedRotatedProfileKey: OWSAES256Key?,
        authedAccount: AuthedAccount
    ) -> Promise<Void> {
        Logger.info("")

        return databaseStorage.write { tx in
            let profileGivenName: String?
            let profileFamilyName: String?
            let profileBio: String?
            let profileBioEmoji: String?
            let profileAvatarData: Data?
            let visibleBadgeIds: [String]
            let userProfileWriter: UserProfileWriter
            if let pendingUpdate = currentPendingProfileUpdate(transaction: tx) {
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
            return updateLocalProfile(
                profileGivenName: profileGivenName,
                profileFamilyName: profileFamilyName,
                profileBio: profileBio,
                profileBioEmoji: profileBioEmoji,
                profileAvatarData: profileAvatarData,
                visibleBadgeIds: visibleBadgeIds,
                unsavedRotatedProfileKey: unsavedRotatedProfileKey,
                userProfileWriter: userProfileWriter,
                authedAccount: authedAccount,
                tx: tx
            )
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    func objc_allWhitelistedRegisteredAddresses(tx: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        var addresses = Set<SignalServiceAddress>()
        for serviceIdString in whitelistedServiceIdsStore.allKeys(transaction: tx) {
            addresses.insert(SignalServiceAddress(serviceIdString: serviceIdString))
        }
        for phoneNumber in whitelistedPhoneNumbersStore.allKeys(transaction: tx) {
            addresses.insert(SignalServiceAddress(phoneNumber: phoneNumber))
        }

        return Array(
            SignalRecipientFinder().signalRecipients(for: Array(addresses), tx: tx)
                .lazy.filter { $0.isRegistered }.map { $0.address }
        )
    }

    @objc
    internal func rotateLocalProfileKeyIfNecessary() {
        DispatchQueue.global().async {
            self.databaseStorage.write { tx in
                self.rotateProfileKeyIfNecessary(tx: tx)
            }
        }
    }

    private func rotateProfileKeyIfNecessary(tx: SDSAnyWriteTransaction) {
        if CurrentAppContext().isNSE || !AppReadiness.isAppReady {
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
                    self.groupsV2.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: tx)
                    self.setLastGroupProfileKeyCheckTimestamp(tx: tx)
                    tx.addAsyncCompletionOffMain {
                        self.groupsV2.processProfileKeyUpdates()
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
        var needsAnotherRotation = false

        let rotationStartDate = Date()

        Logger.info("Beginning profile key rotation.")

        // The order of operations here is very important to prevent races between
        // when we rotate our profile key and reupload our profile. It's essential
        // we avoid a case where other devices are operating with a *new* profile
        // key that we have yet to upload a profile for.

        return firstly(on: DispatchQueue.global()) { () -> Promise<OWSAES256Key> in
            Logger.info("Reuploading profile with new profile key")

            // We re-upload our local profile with the new profile key *before* we
            // persist it. This is safe, because versioned profiles allow other clients
            // to continue using our old profile key with the old version of our
            // profile. It is possible this operation will fail, in which case we will
            // try to rotate your profile key again on the next app launch or blocklist
            // change and continue to use the old profile key.

            let newProfileKey = OWSAES256Key.generateRandom()
            return self.reuploadLocalProfileWithSneakyTransaction(
                unsavedRotatedProfileKey: newProfileKey,
                authedAccount: authedAccount
            ).map { newProfileKey }
        }.then(on: DispatchQueue.global()) { newProfileKey -> Promise<Void> in
            guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
                throw OWSAssertionError("Missing localAci.")
            }

            Logger.info("Persisting rotated profile key and kicking off subsequent operations.")

            return self.databaseStorage.write(.promise) { transaction in
                self.setLocalProfileKey(
                    newProfileKey,
                    userProfileWriter: .localUser,
                    authedAccount: authedAccount,
                    transaction: transaction
                )

                // Whenever a user's profile key changes, we need to fetch a new profile
                // key credential for them.
                self.versionedProfiles.clearProfileKeyCredential(for: AciObjC(localAci), transaction: transaction)

                // We schedule the updates here but process them below using
                // processProfileKeyUpdates. It's more efficient to process them after the
                // intermediary steps are done.
                self.groupsV2.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: transaction)

                triggers.forEach { trigger in
                    switch trigger {
                    case .blocklistChange(let values):
                        self.didRotateProfileKeyFromBlocklistTrigger(values, tx: transaction)
                    case .recipientHiding(let triggerDate):
                        needsAnotherRotation = needsAnotherRotation || self.didRotateProfileKeyFromHidingTrigger(
                            rotationStartDate: rotationStartDate,
                            triggerDate: triggerDate,
                            tx: transaction
                        )
                    case .leftGroupWithHiddenOrBlockedRecipient(let triggerDate):
                        needsAnotherRotation = needsAnotherRotation || self.didRotateProfileKeyFromLeaveGroupTrigger(
                            rotationStartDate: rotationStartDate,
                            triggerDate: triggerDate,
                            tx: transaction
                        )
                    }
                }
            }
        }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
            Logger.info("Updating account attributes after profile key rotation.")
            return Promise.wrapAsync {
                try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: authedAccount)
            }
        }.done(on: DispatchQueue.global()) {
            Logger.info("Completed profile key rotation.")
            self.groupsV2.processProfileKeyUpdates()
        }.ensure {
            self.isRotatingProfileKey = false
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
            transaction: tx
        )
        self.whitelistedServiceIdsStore.removeValues(
            forKeys: trigger.serviceIds.map { $0.serviceIdUppercaseString },
            transaction: tx
        )
        self.whitelistedGroupsStore.removeValues(
            forKeys: trigger.groupIds.map { self.groupKey(forGroupId: $0) },
            transaction: tx
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
        let allWhitelistedNumbers = whitelistedPhoneNumbersStore.allKeys(transaction: tx)

        return allWhitelistedNumbers.filter { candidate in
            let address = SignalServiceAddress(phoneNumber: candidate)
            return blockingManager.isAddressBlocked(address, transaction: tx)
        }
    }

    private func blockedServiceIdsInWhitelist(tx: SDSAnyReadTransaction) -> [ServiceId] {
        let allWhitelistedServiceIds = whitelistedServiceIdsStore.allKeys(transaction: tx).compactMap {
            try? ServiceId.parseFrom(serviceIdString: $0)
        }

        return allWhitelistedServiceIds.filter { candidate in
            return blockingManager.isAddressBlocked(SignalServiceAddress(candidate), transaction: tx)
        }
    }

    private func blockedGroupIDsInWhitelist(tx: SDSAnyReadTransaction) -> [Data] {
        let allWhitelistedGroupKeys = whitelistedGroupsStore.allKeys(transaction: tx)

        return allWhitelistedGroupKeys.lazy
            .compactMap { self.groupIdForGroupKey($0) }
            .filter { blockingManager.isGroupIdBlocked($0, transaction: tx) }
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

    static func swift_normalizeRecipientInProfileWhitelist(
        _ recipient: SignalRecipient,
        serviceIdStore: KeyValueStore,
        phoneNumberStore: KeyValueStore,
        tx: DBWriteTransaction
    ) {
        // First, we figure out which identifiers are whitelisted.
        let orderedIdentifiers: [(store: KeyValueStore, key: String, isInWhitelist: Bool)] = [
            (serviceIdStore, recipient.aci?.serviceIdUppercaseString),
            (phoneNumberStore, recipient.phoneNumber),
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

    // This will re-upload the existing local profile state.
    @objc
    @available(swift, obsoleted: 1.0)
    func reuploadLocalProfileWithSneakyTransaction(authedAccount: AuthedAccount) -> AnyPromise {
        return AnyPromise(reuploadLocalProfileWithSneakyTransaction(unsavedRotatedProfileKey: nil, authedAccount: authedAccount))
    }

    @objc
    class func updateStorageServiceIfNecessary() {
        guard
            CurrentAppContext().isMainApp,
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice
        else {
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

    // MARK: - Other User's Profiles

    @objc
    func setProfileKeyData(
        _ profileKeyData: Data,
        forAddress addressParam: SignalServiceAddress,
        onlyFillInIfMissing: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction tx: SDSAnyWriteTransaction
    ) {
        let address = OWSUserProfile.resolve(addressParam)

        guard let profileKey = OWSAES256Key(data: profileKeyData) else {
            owsFailDebug("Invalid profile key data.")
            return
        }

        let userProfile = OWSUserProfile.getOrBuildUserProfile(for: address, authedAccount: authedAccount, transaction: tx)

        if onlyFillInIfMissing, userProfile.profileKey != nil {
            return
        }

        if profileKey.keyData == userProfile.profileKey?.keyData {
            return
        }

        if let addressAci = addressParam.serviceId as? Aci {
            // Whenever a user's profile key changes, we need to fetch a new
            // profile key credential for them.
            versionedProfiles.clearProfileKeyCredential(for: AciObjC(addressAci), transaction: tx)
        }

        // If this is the profile for the local user, we always want to defer to local state
        // so skip the update profile for address call.
        let isLocalAddress = OWSUserProfile.isLocalProfileAddress(address) || authedAccount.isAddressForLocalUser(address)
        if !isLocalAddress, let serviceId = address.serviceId {
            udManager.setUnidentifiedAccessMode(.unknown, for: serviceId, tx: tx)
            tx.addAsyncCompletionOffMain {
                self.fetchProfile(for: address, authedAccount: authedAccount)
            }
        }

        userProfile.update(
            profileKey: profileKey,
            userProfileWriter: userProfileWriter,
            authedAccount: authedAccount,
            transaction: tx,
            completion: nil
        )
    }

    // MARK: - Bulk Fetching

    private func userProfilesRefinery(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> Refinery<SignalServiceAddress, OWSUserProfile> {
        let resolvedAddresses = addresses.map { OWSUserProfile.resolve($0) }

        return .init(resolvedAddresses).refine(condition: { address in
            OWSUserProfile.isLocalProfileAddress(address)
        }, then: { localAddresses in
            lazy var profile = { self.getLocalUserProfile(with: tx) }()
            return localAddresses.lazy.map { _ in profile }
        }, otherwise: { remoteAddresses in
            return self.modelReadCaches.userProfileReadCache.getUserProfiles(for: remoteAddresses, transaction: tx)
        })
    }

    // MARK: -

    private class var avatarUrlSession: OWSURLSessionProtocol {
        return self.signalService.urlSessionForCdn(cdnNumber: 0)
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
        var authedAccount: AuthedAccount
        var future: Future<Void>
    }

    @discardableResult
    private func _updateProfileOnServiceIfNecessary(retryDelay: TimeInterval = 1) -> UpdateProfileStatus {
        AssertIsOnMainThread()

        guard AppReadiness.isAppReady else {
            return .notReady
        }
        guard !isUpdatingProfileOnService else {
            // Avoid having two redundant updates in flight at the same time.
            return .notReady
        }

        let pendingUpdate = databaseStorage.read { tx in
            return currentPendingProfileUpdate(transaction: tx)
        }
        guard let pendingUpdate else {
            return .notNeeded
        }

        guard let (future, authedAccount) = processProfileUpdateRequests(upThrough: pendingUpdate.id) else {
            return .notReady
        }

        isUpdatingProfileOnService = true

        Task { @MainActor in
            // We must be on the MainActor to touch isUpdatingProfileOnService.
            defer {
                isUpdatingProfileOnService = false
            }
            do {
                try await attemptToUpdateProfileOnService(update: pendingUpdate, authedAccount: authedAccount)
                if pendingUpdate.unsavedRotatedProfileKey == nil {
                    _ = try await fetchLocalUsersProfile(mainAppOnly: false, authedAccount: authedAccount).awaitable()
                }
                DispatchQueue.global().async {
                    future?.resolve()
                }
                DispatchQueue.main.async {
                    self._updateProfileOnServiceIfNecessary()
                }
            } catch {
                DispatchQueue.global().async {
                    future?.reject(error)
                }
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
    private func processProfileUpdateRequests(upThrough requestId: UUID) -> (Future<Void>?, AuthedAccount)? {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let isRegistered = tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered

        // Find the AuthedAccount & Future for the request. This will generally
        // exist for the initial request but will be nil for any retries.
        let pendingRequests: (canceledRequests: [ProfileUpdateRequest], result: (Future<Void>?, AuthedAccount)?)
        pendingRequests = swiftValues.pendingUpdateRequests.update { mutableRequests in
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
                return (canceledRequests, (currentRequest?.future, authedAccount))
            case .implicit:
                return (canceledRequests, nil)
            }
        }

        for canceledRequest in pendingRequests.canceledRequests {
            canceledRequest.future.reject(OWSGenericError("Canceled because a new request was enqueued."))
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
            self.localProfileAvatarData() != nil
        else {
            clearAvatarRepairNeeded()
            return
        }

        Self.avatarRepairPromise = firstly {
            reuploadLocalProfileWithSneakyTransaction(unsavedRotatedProfileKey: nil, authedAccount: authedAccount)
        }.done { _ in
            Logger.info("Avatar repair succeeded.")
            self.clearAvatarRepairNeeded()
            Self.avatarRepairPromise = nil
        }.catch { error in
            Logger.error("Avatar repair failed: \(error)")
            self.incrementAvatarRepairAttempts()
            Self.avatarRepairPromise = nil
        }
    }

    private static let maxAvataraRepairAttempts = 5

    private func avatairRepairAttemptCount(_ transaction: SDSAnyReadTransaction) -> Int {
        let store = SDSKeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
        return store.getInt(GRDBSchemaMigrator.avatarRepairAttemptCount,
                            defaultValue: Self.maxAvataraRepairAttempts,
                            transaction: transaction)
    }

    private func avatarRepairNeeded() -> Bool {
        return self.databaseStorage.read { transaction in
            let count = avatairRepairAttemptCount(transaction)
            return count < Self.maxAvataraRepairAttempts
        }
    }

    private func incrementAvatarRepairAttempts() {
        databaseStorage.write { transaction in
            let store = SDSKeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
            store.setInt(avatairRepairAttemptCount(transaction) + 1,
                         key: GRDBSchemaMigrator.avatarRepairAttemptCount,
                         transaction: transaction)
        }
    }

    private func clearAvatarRepairNeeded() {
        databaseStorage.write { transaction in
            let store = SDSKeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
            store.removeValue(forKey: GRDBSchemaMigrator.avatarRepairAttemptCount, transaction: transaction)
        }
    }

    private func attemptToUpdateProfileOnService(
        update: PendingProfileUpdate,
        authedAccount: AuthedAccount
    ) async throws {
        // We capture the local user profile early to eliminate the risk of opening
        // a transaction within a transaction.
        let userProfile = profileManagerImpl.localUserProfile()

        let attempt = ProfileUpdateAttempt(update: update, userProfile: userProfile)

        do {
            try await writeProfileAvatarToDisk(attempt: attempt).awaitable()
            try await Self.updateProfileOnServiceVersioned(attempt: attempt, authedAccount: authedAccount).awaitable()
            await databaseStorage.awaitableWrite { tx in
                if self.tryToDequeueProfileUpdate(update: attempt.update, transaction: tx) {
                    Self.updateLocalProfile(with: attempt, authedAccount: authedAccount, transaction: tx)
                }
                // Notify all our devices that the profile has changed.
                let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read)
                if tsRegistrationState.isRegistered {
                    self.syncManager.sendFetchLatestProfileSyncMessage(tx: tx)
                }
            }
        } catch let error where error.isNetworkFailureOrTimeout {
            // We retry network errors forever (with exponential backoff).
            throw error
        } catch {
            // Other errors cause us to give up immediately.
            await databaseStorage.awaitableWrite { tx in
                _ = self.tryToDequeueProfileUpdate(update: attempt.update, transaction: tx)
            }
            throw error
        }
    }

    private func writeProfileAvatarToDisk(attempt: ProfileUpdateAttempt) -> Promise<Void> {
        guard let profileAvatarData = attempt.update.profileAvatarData else {
            return Promise.value(())
        }
        return Promise(on: DispatchQueue.global()) { future in
            let filename = self.generateAvatarFilename()
            let filePath = OWSUserProfile.profileAvatarFilepath(withFilename: filename)
            do {
                try profileAvatarData.write(to: URL(fileURLWithPath: filePath), options: [.atomic])
                attempt.avatarFilename = filename
                future.resolve()
            } catch {
                future.reject(OWSError(error: .avatarWriteFailed, description: "Avatar write failed.", isRetryable: false))
            }
        }
    }

    private class func updateProfileOnServiceVersioned(
        attempt: ProfileUpdateAttempt,
        authedAccount: AuthedAccount
    ) -> Promise<Void> {
        Logger.info("avatar?: \(attempt.update.profileAvatarData != nil), " +
                        "profileGivenName?: \(attempt.update.profileGivenName != nil), " +
                        "profileFamilyName?: \(attempt.update.profileFamilyName != nil), " +
                        "profileBio?: \(attempt.update.profileBio != nil), " +
                        "profileBioEmoji?: \(attempt.update.profileBioEmoji != nil) " +
                        "visibleBadges?: \(attempt.update.visibleBadgeIds.count).")
        return firstly(on: DispatchQueue.global()) {
            Self.versionedProfilesSwift.updateProfilePromise(
                profileGivenName: attempt.update.profileGivenName,
                profileFamilyName: attempt.update.profileFamilyName,
                profileBio: attempt.update.profileBio,
                profileBioEmoji: attempt.update.profileBioEmoji,
                profileAvatarData: attempt.update.profileAvatarData,
                visibleBadgeIds: attempt.update.visibleBadgeIds,
                unsavedRotatedProfileKey: attempt.update.unsavedRotatedProfileKey,
                authedAccount: authedAccount
            )
        }.map(on: DispatchQueue.global()) { versionedUpdate in
            attempt.avatarUrlPath = versionedUpdate.avatarUrlPath
        }
    }

    private class func updateLocalProfile(
        with attempt: ProfileUpdateAttempt,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        attempt.userProfile.update(
            givenName: attempt.update.profileGivenName,
            familyName: attempt.update.profileFamilyName,
            avatarUrlPath: attempt.avatarUrlPath,
            avatarFileName: attempt.avatarFilename,
            userProfileWriter: attempt.userProfileWriter,
            authedAccount: authedAccount,
            transaction: transaction,
            completion: nil
        )
    }

    // MARK: - Update Queue

    private static let kPendingProfileUpdateKey = "kPendingProfileUpdateKey"

    private func enqueueProfileUpdate(
        profileGivenName: String?,
        profileFamilyName: String?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarData: Data?,
        visibleBadgeIds: [String],
        unsavedRotatedProfileKey: OWSAES256Key?,
        userProfileWriter: UserProfileWriter,
        tx: SDSAnyWriteTransaction
    ) -> PendingProfileUpdate {
        // Note that this might overwrite a pending profile update.
        // That's desirable.  We only ever want to retain the
        // latest changes.
        let update = PendingProfileUpdate(
            profileGivenName: profileGivenName,
            profileFamilyName: profileFamilyName,
            profileBio: profileBio,
            profileBioEmoji: profileBioEmoji,
            profileAvatarData: profileAvatarData,
            visibleBadgeIds: visibleBadgeIds,
            unsavedRotatedProfileKey: unsavedRotatedProfileKey,
            userProfileWriter: userProfileWriter
        )
        settingsStore.setObject(update, key: Self.kPendingProfileUpdateKey, transaction: tx)
        return update
    }

    private func currentPendingProfileUpdate(transaction: SDSAnyReadTransaction) -> PendingProfileUpdate? {
        guard let value = settingsStore.getObject(forKey: Self.kPendingProfileUpdateKey, transaction: transaction) else {
            return nil
        }
        guard let update = value as? PendingProfileUpdate else {
            owsFailDebug("Invalid value.")
            return nil
        }
        return update
    }

    private func isCurrentPendingProfileUpdate(update: PendingProfileUpdate, transaction: SDSAnyReadTransaction) -> Bool {
        guard let currentUpdate = currentPendingProfileUpdate(transaction: transaction) else {
            return false
        }
        return update.hasSameIdAs(currentUpdate)
    }

    private func tryToDequeueProfileUpdate(update: PendingProfileUpdate, transaction: SDSAnyWriteTransaction) -> Bool {
        guard isCurrentPendingProfileUpdate(update: update, transaction: transaction) else {
            Logger.warn("Ignoring stale update completion.")
            return false
        }
        settingsStore.removeValue(forKey: Self.kPendingProfileUpdateKey, transaction: transaction)
        return true
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
        return self.metadataStore.getDate(Self.kLastGroupProfileKeyCheckTimestampKey, transaction: tx)
    }

    private func setLastGroupProfileKeyCheckTimestamp(tx: SDSAnyWriteTransaction) {
        return self.metadataStore.setDate(Date(), key: Self.kLastGroupProfileKeyCheckTimestampKey, transaction: tx)
    }

    private static let recipientHidingTriggerTimestampKey = "recipientHidingTriggerTimestampKey"

    private func recipientHidingTriggerTimestamp(tx: SDSAnyReadTransaction) -> Date? {
        return self.metadataStore.getDate(Self.recipientHidingTriggerTimestampKey, transaction: tx)
    }

    private func setRecipientHidingTriggerTimestamp(_ date: Date?, tx: SDSAnyWriteTransaction) {
        guard let date else {
            self.metadataStore.removeValue(forKey: Self.recipientHidingTriggerTimestampKey, transaction: tx)
            return
        }
        return self.metadataStore.setDate(date, key: Self.recipientHidingTriggerTimestampKey, transaction: tx)
    }

    private static let leaveGroupTriggerTimestampKey = "leaveGroupTriggerTimestampKey"

    private func leaveGroupTriggerTimestamp(tx: SDSAnyReadTransaction) -> Date? {
        return self.metadataStore.getDate(Self.leaveGroupTriggerTimestampKey, transaction: tx)
    }

    private func setLeaveGroupTriggerTimestamp(_ date: Date?, tx: SDSAnyWriteTransaction) {
        guard let date else {
            self.metadataStore.removeValue(forKey: Self.leaveGroupTriggerTimestampKey, transaction: tx)
            return
        }
        return self.metadataStore.setDate(date, key: Self.leaveGroupTriggerTimestampKey, transaction: tx)
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

    private static let serialQueue = DispatchQueue(label: "org.signal.profile-manager")

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

        return firstly(on: DispatchQueue.global()) { () throws -> Promise<OWSUrlDownloadResponse> in
            let urlSession = self.avatarUrlSession
            return urlSession.downloadTaskPromise(avatarUrlPath, method: .get)
        }.map(on: DispatchQueue.global()) { (response: OWSUrlDownloadResponse) -> Data in
            do {
                return try Data(contentsOf: response.downloadUrl)
            } catch {
                owsFailDebug("Could not load data failed: \(error)")
                // Fail immediately; do not retry.
                throw SSKUnretryableError.couldNotLoadFileData
            }
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<Data> in
            throw error
        }.map(on: DispatchQueue.global()) { (encryptedData: Data) -> Data in
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
