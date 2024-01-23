//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit
import SignalServiceKit

class OWSProfileManagerSwiftValues {
    fileprivate let pendingUpdateRequests = AtomicValue<[OWSProfileManager.ProfileUpdateRequest]>([], lock: AtomicLock())
    fileprivate let avatarDownloadRequests = AtomicValue<[OWSProfileManager.AvatarDownloadKey: Promise<Data>]>([:], lock: AtomicLock())
}

extension OWSProfileManager: ProfileManager {
    public func fullNames(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [String?] {
        return userProfilesRefinery(for: addresses, tx: tx).values.map { $0?.fullName }
    }

    public func fetchLocalUsersProfile(mainAppOnly: Bool, authedAccount: AuthedAccount) -> Promise<FetchedProfile> {
        do {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            return ProfileFetcherJob.fetchProfilePromise(
                serviceId: try tsAccountManager.localIdentifiersWithMaybeSneakyTransaction(authedAccount: authedAccount).aci,
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
        profileGivenName: OptionalChange<OWSUserProfile.NameComponent>,
        profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>,
        profileBio: OptionalChange<String?>,
        profileBioEmoji: OptionalChange<String?>,
        profileAvatarData: OptionalChange<Data?>,
        visibleBadgeIds: OptionalChange<[String]>,
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

    // This will re-upload the existing local profile state.
    public func reuploadLocalProfile(
        unsavedRotatedProfileKey: OWSAES256Key?,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        Logger.info("")

        let profileChanges = currentPendingProfileChanges(tx: SDSDB.shimOnlyBridge(tx))
        return updateLocalProfile(
            profileGivenName: profileChanges?.profileGivenName ?? .noChange,
            profileFamilyName: profileChanges?.profileFamilyName ?? .noChange,
            profileBio: profileChanges?.profileBio ?? .noChange,
            profileBioEmoji: profileChanges?.profileBioEmoji ?? .noChange,
            profileAvatarData: profileChanges?.profileAvatarData ?? .noChange,
            visibleBadgeIds: profileChanges?.visibleBadgeIds ?? .noChange,
            unsavedRotatedProfileKey: unsavedRotatedProfileKey,
            userProfileWriter: profileChanges?.userProfileWriter ?? .reupload,
            authedAccount: authedAccount,
            tx: SDSDB.shimOnlyBridge(tx)
        )
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

            let newProfileKey = OWSAES256Key.generateRandom()
            let uploadPromise = await self.databaseStorage.awaitableWrite { tx in
                self.reuploadLocalProfile(unsavedRotatedProfileKey: newProfileKey, authedAccount: authedAccount, tx: tx.asV2Write)
            }
            try await uploadPromise.awaitable()

            guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
                throw OWSAssertionError("Missing localAci.")
            }

            Logger.info("Persisting rotated profile key and kicking off subsequent operations.")

            let needsAnotherRotation = await self.databaseStorage.awaitableWrite { tx in
                self.setLocalProfileKey(
                    newProfileKey,
                    userProfileWriter: .localUser,
                    authedAccount: authedAccount,
                    transaction: tx
                )

                // Whenever a user's profile key changes, we need to fetch a new profile
                // key credential for them.
                self.versionedProfiles.clearProfileKeyCredential(for: AciObjC(localAci), transaction: tx)

                // We schedule the updates here but process them below using
                // processProfileKeyUpdates. It's more efficient to process them after the
                // intermediary steps are done.
                self.groupsV2.scheduleAllGroupsV2ForProfileKeyUpdate(transaction: tx)

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
            self.groupsV2.processProfileKeyUpdates()

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
        return AnyPromise(databaseStorage.write { tx in
            reuploadLocalProfile(unsavedRotatedProfileKey: nil, authedAccount: authedAccount, tx: tx.asV2Write)
        })
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
        var requestParameters: Parameters
        var authedAccount: AuthedAccount

        struct Parameters {
            var profileKey: OWSAES256Key?
            var future: Future<Void>
        }
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

        let profileChanges = databaseStorage.read { tx in
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
            self.localProfileAvatarData() != nil
        else {
            databaseStorage.write { tx in clearAvatarRepairNeeded(tx: tx) }
            return
        }

        Self.avatarRepairPromise = Promise.wrapAsync { @MainActor in
            defer {
                Self.avatarRepairPromise = nil
            }
            do {
                let uploadPromise = await self.databaseStorage.awaitableWrite { tx in
                    return self.reuploadLocalProfile(unsavedRotatedProfileKey: nil, authedAccount: authedAccount, tx: tx.asV2Write)
                }
                try await uploadPromise.awaitable()
                Logger.info("Avatar repair succeeded.")
                await self.databaseStorage.awaitableWrite { tx in self.clearAvatarRepairNeeded(tx: tx) }
            } catch {
                Logger.warn("Avatar repair failed: \(error)")
                await self.databaseStorage.awaitableWrite { tx in self.incrementAvatarRepairAttempts(tx: tx) }
            }
        }
    }

    private static let maxAvatarRepairAttempts = 5

    private func avatairRepairAttemptCount(_ transaction: SDSAnyReadTransaction) -> Int {
        let store = SDSKeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
        return store.getInt(GRDBSchemaMigrator.avatarRepairAttemptCount,
                            defaultValue: Self.maxAvatarRepairAttempts,
                            transaction: transaction)
    }

    private func avatarRepairNeeded() -> Bool {
        return self.databaseStorage.read { transaction in
            let count = avatairRepairAttemptCount(transaction)
            return count < Self.maxAvatarRepairAttempts
        }
    }

    private func incrementAvatarRepairAttempts(tx: SDSAnyWriteTransaction) {
        let store = SDSKeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
        store.setInt(avatairRepairAttemptCount(tx) + 1, key: GRDBSchemaMigrator.avatarRepairAttemptCount, transaction: tx)
    }

    private func clearAvatarRepairNeeded(tx: SDSAnyWriteTransaction) {
        let store = SDSKeyValueStore(collection: GRDBSchemaMigrator.migrationSideEffectsCollectionName)
        store.removeValue(forKey: GRDBSchemaMigrator.avatarRepairAttemptCount, transaction: tx)
    }

    private func updateProfileOnService(
        profileChanges: PendingProfileUpdate,
        newProfileKey: OWSAES256Key?,
        authedAccount: AuthedAccount
    ) async throws {
        do {
            let avatarUpdate = try await buildAvatarUpdate(
                avatarChange: profileChanges.profileAvatarData,
                isRotatingProfileKey: newProfileKey != nil,
                authedAccount: authedAccount
            )

            // We capture the local user profile early to eliminate the risk of opening
            // a transaction within a transaction.
            let userProfile = profileManagerImpl.localUserProfile()
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
                newGivenName = userProfile.unfilteredGivenName.flatMap { OWSUserProfile.NameComponent(truncating: $0) }
            }
            let newFamilyName = profileChanges.profileFamilyName.orExistingValue(
                userProfile.unfilteredFamilyName.flatMap { OWSUserProfile.NameComponent(truncating: $0) }
            )
            let newBio = profileChanges.profileBio.orExistingValue(userProfile.bio)
            let newBioEmoji = profileChanges.profileBioEmoji.orExistingValue(userProfile.bioEmoji)
            let newVisibleBadgeIds = profileChanges.visibleBadgeIds.orExistingValue(userProfile.visibleBadges.map { $0.badgeId })

            let versionedUpdate = try await Self.versionedProfilesSwift.updateProfile(
                profileGivenName: newGivenName,
                profileFamilyName: newFamilyName,
                profileBio: newBio,
                profileBioEmoji: newBioEmoji,
                profileAvatarMutation: avatarUpdate.remoteMutation,
                visibleBadgeIds: newVisibleBadgeIds,
                profileKey: profileKey,
                authedAccount: authedAccount
            )
            await databaseStorage.awaitableWrite { tx in
                self.tryToDequeueProfileChanges(profileChanges, tx: tx)
                // Apply the changes to our local profile.
                let userProfile = OWSUserProfile.getOrBuildUserProfile(
                    for: OWSUserProfile.localProfileAddress,
                    authedAccount: authedAccount,
                    transaction: tx
                )
                userProfile.update(
                    givenName: newGivenName?.stringValue.rawValue,
                    familyName: newFamilyName?.stringValue.rawValue,
                    bio: newBio,
                    bioEmoji: newBioEmoji,
                    avatarUrlPath: versionedUpdate.avatarUrlPath.orExistingValue(userProfile.avatarUrlPath),
                    avatarFileName: avatarUpdate.filenameChange.orExistingValue(userProfile.avatarFileName),
                    userProfileWriter: profileChanges.userProfileWriter,
                    authedAccount: authedAccount,
                    transaction: tx,
                    completion: nil
                )
                // Notify all our devices that the profile has changed.
                let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read)
                if tsRegistrationState.isRegistered {
                    self.syncManager.sendFetchLatestProfileSyncMessage(tx: tx)
                }
            }
            // If we're changing the profile key, then the normal "fetch our profile"
            // method will fail because it will the just-obsoleted profile key.
            if newProfileKey == nil {
                _ = try await fetchLocalUsersProfile(mainAppOnly: false, authedAccount: authedAccount).awaitable()
            }
        } catch let error where error.isNetworkFailureOrTimeout {
            // We retry network errors forever (with exponential backoff).
            throw error
        } catch {
            // Other errors cause us to give up immediately.
            await databaseStorage.awaitableWrite { tx in self.tryToDequeueProfileChanges(profileChanges, tx: tx) }
            throw error
        }
    }

    /// Computes necessary changes to the avatar.
    ///
    /// Most fields are re-encrypted with every update. However, the avatar can
    /// be large, so we only update it if absolutely necessary. We must update
    /// the profile avatar in two cases:
    ///   (1) The avatar has changed (duh!).
    ///   (2) The profile key has changed.
    /// In the former case, we'll always have the new avatar because we're
    /// actively changing it. In the latter case, another device may have
    /// changed it, so we may need to download it to re-encrypt it.
    private func buildAvatarUpdate(
        avatarChange: OptionalChange<Data?>,
        isRotatingProfileKey: Bool,
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
        case .noChange:
            // This is case (2).
            if isRotatingProfileKey {
                do {
                    try await _downloadAndDecryptAvatarIfNeeded(
                        internalAddress: OWSUserProfile.localProfileAddress,
                        authedAccount: authedAccount
                    )
                } catch where !error.isNetworkFailureOrTimeout {
                    // Ignore the error because it's not likely to go away if we retry. If we
                    // can't decrypt the existing avatar, then we don't really have any choice
                    // other than blowing it away.
                }
                if let avatarFilename = localUserProfile().avatarFileName, let avatarData = localProfileAvatarData() {
                    return (.changeAvatar(avatarData), .setTo(avatarFilename))
                }
                return (.clearAvatar, .setTo(nil))
            }
            // We aren't changing the avatar, so use the existing value.
            if localUserProfile().avatarUrlPath != nil {
                return (.keepAvatar, .noChange)
            }
            return (.clearAvatar, .setTo(nil))
        }
    }

    private func writeProfileAvatarToDisk(avatarData: Data) throws -> String {
        let filename = self.generateAvatarFilename()
        let filePath = OWSUserProfile.profileAvatarFilepath(withFilename: filename)
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
        profileAvatarData: OptionalChange<Data?>,
        visibleBadgeIds: OptionalChange<[String]>,
        unsavedRotatedProfileKey: OWSAES256Key?,
        userProfileWriter: UserProfileWriter,
        tx: SDSAnyWriteTransaction
    ) -> PendingProfileUpdate {
        let oldChanges = currentPendingProfileChanges(tx: tx)
        let newChanges = PendingProfileUpdate(
            profileGivenName: profileGivenName.orElseIfNoChange(oldChanges?.profileGivenName ?? .noChange),
            profileFamilyName: profileFamilyName.orElseIfNoChange(oldChanges?.profileFamilyName ?? .noChange),
            profileBio: profileBio.orElseIfNoChange(oldChanges?.profileBio ?? .noChange),
            profileBioEmoji: profileBioEmoji.orElseIfNoChange(oldChanges?.profileBioEmoji ?? .noChange),
            profileAvatarData: profileAvatarData.orElseIfNoChange(oldChanges?.profileAvatarData ?? .noChange),
            visibleBadgeIds: visibleBadgeIds.orElseIfNoChange(oldChanges?.visibleBadgeIds ?? .noChange),
            userProfileWriter: userProfileWriter
        )
        settingsStore.setObject(newChanges, key: Self.kPendingProfileUpdateKey, transaction: tx)
        return newChanges
    }

    private func currentPendingProfileChanges(tx: SDSAnyReadTransaction) -> PendingProfileUpdate? {
        guard let value = settingsStore.getObject(forKey: Self.kPendingProfileUpdateKey, transaction: tx) else {
            return nil
        }
        guard let profileChanges = value as? PendingProfileUpdate else {
            owsFailDebug("Invalid value.")
            return nil
        }
        return profileChanges
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
        settingsStore.removeValue(forKey: Self.kPendingProfileUpdateKey, transaction: tx)
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

    let profileGivenName: OptionalChange<OWSUserProfile.NameComponent>
    let profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>
    let profileBio: OptionalChange<String?>
    let profileBioEmoji: OptionalChange<String?>
    let profileAvatarData: OptionalChange<Data?>
    let visibleBadgeIds: OptionalChange<[String]>

    let userProfileWriter: UserProfileWriter

    init(
        profileGivenName: OptionalChange<OWSUserProfile.NameComponent>,
        profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>,
        profileBio: OptionalChange<String?>,
        profileBioEmoji: OptionalChange<String?>,
        profileAvatarData: OptionalChange<Data?>,
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

    private static func normalizeAvatar(_ avatarData: OptionalChange<Data?>) -> OptionalChange<Data?> {
        return avatarData.map { $0?.nilIfEmpty }
    }

    // MARK: - NSCoding

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
        Self.encodeOptionalChange(profileAvatarData, for: .profileAvatarData, with: aCoder)
        Self.encodeVisibleBadgeIds(visibleBadgeIds, for: .visibleBadgeIds, with: aCoder)
        aCoder.encodeCInt(Int32(userProfileWriter.rawValue), forKey: NSCodingKeys.userProfileWriter.rawValue)
    }

    private static func decodeOptionalChange<T>(for codingKey: NSCodingKeys, with aDecoder: NSCoder) -> OptionalChange<T?> {
        if aDecoder.containsValue(forKey: codingKey.changedKey), !aDecoder.decodeBool(forKey: codingKey.changedKey) {
            return .noChange
        }
        return .setTo(aDecoder.decodeObject(forKey: codingKey.rawValue) as? T? ?? nil)
    }

    private static func decodeOptionalNameChange(
        for codingKey: NSCodingKeys,
        with aDecoder: NSCoder
    ) -> OptionalChange<OWSUserProfile.NameComponent?> {
        let stringChange: OptionalChange<String?> = decodeOptionalChange(for: codingKey, with: aDecoder)
        switch stringChange {
        case .noChange:
            return .noChange
        case .setTo(.none):
            return .setTo(nil)
        case .setTo(.some(let value)):
            // We shouldn't be able to encode an invalid value. If we do, fall back to
            // `.noChange` rather than clearing it.
            guard let nameComponent = OWSUserProfile.NameComponent(truncating: value) else {
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
        guard let visibleBadgeIds = aDecoder.decodeObject(forKey: codingKey.rawValue) as? [String] else {
            return .noChange
        }
        return .setTo(visibleBadgeIds)
    }

    public required init?(coder aDecoder: NSCoder) {
        guard
            let idString = aDecoder.decodeObject(forKey: NSCodingKeys.id.rawValue) as? String,
            let id = UUID(uuidString: idString)
        else {
            owsFailDebug("Missing id")
            return nil
        }
        self.id = id
        self.profileGivenName = Self.decodeRequiredNameChange(for: .profileGivenName, with: aDecoder)
        self.profileFamilyName = Self.decodeOptionalNameChange(for: .profileFamilyName, with: aDecoder)
        self.profileBio = Self.decodeOptionalChange(for: .profileBio, with: aDecoder)
        self.profileBioEmoji = Self.decodeOptionalChange(for: .profileBioEmoji, with: aDecoder)
        self.profileAvatarData = Self.normalizeAvatar(Self.decodeOptionalChange(for: .profileAvatarData, with: aDecoder))
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

    @objc
    func downloadAndDecryptAvatarIfNeededObjC(userProfile: OWSUserProfile, authedAccount: AuthedAccount) {
        Task {
            try await self.downloadAndDecryptAvatarIfNeeded(userProfile: userProfile, authedAccount: authedAccount)
        }
    }

    public func downloadAndDecryptAvatarIfNeeded(userProfile: OWSUserProfile, authedAccount: AuthedAccount) async throws {
        let backgroundTask = OWSBackgroundTask(label: #function)
        defer { backgroundTask.end() }
        try await _downloadAndDecryptAvatarIfNeeded(internalAddress: userProfile.address, authedAccount: authedAccount)
    }

    private func _downloadAndDecryptAvatarIfNeeded(internalAddress: SignalServiceAddress, authedAccount: AuthedAccount) async throws {
        let oldProfile = databaseStorage.read { tx in OWSUserProfile.getFor(internalAddress, transaction: tx) }
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
            let filename = generateAvatarFilename()
            let filePath = OWSUserProfile.profileAvatarFilepath(withFilename: filename)
            let avatarData = try await downloadAndDecryptAvatar(avatarUrlPath: avatarUrlPath, profileKey: profileKey).awaitable()
            try avatarData.write(to: URL(fileURLWithPath: filePath), options: [.atomic])
            var didConsumeFilePath = false
            defer {
                if !didConsumeFilePath { try? FileManager.default.removeItem(atPath: filePath) }
            }
            guard UIImage(contentsOfFile: filePath) != nil else {
                throw OWSGenericError("Avatar image can't be decoded.")
            }
            (shouldRetry, didConsumeFilePath) = await databaseStorage.awaitableWrite { tx in
                let newProfile = OWSUserProfile.getOrBuildUserProfile(for: internalAddress, authedAccount: authedAccount, transaction: tx)
                guard newProfile.avatarFileName == nil else {
                    return (false, false)
                }
                // If the URL/profileKey change, we have a new avatar to download.
                guard newProfile.profileKey == profileKey, newProfile.avatarUrlPath == avatarUrlPath else {
                    return (true, false)
                }
                newProfile.update(
                    avatarFileName: filename,
                    userProfileWriter: .avatarDownload,
                    authedAccount: authedAccount,
                    transaction: tx
                )
                return (false, true)
            }
        }
        if shouldRetry {
            try await _downloadAndDecryptAvatarIfNeeded(internalAddress: internalAddress, authedAccount: authedAccount)
        }
    }

    public func downloadAndDecryptAvatar(avatarUrlPath: String, profileKey: OWSAES256Key) async throws -> Data {
        try await downloadAndDecryptAvatar(avatarUrlPath: avatarUrlPath, profileKey: profileKey).awaitable()
    }

    fileprivate func downloadAndDecryptAvatar(avatarUrlPath: String, profileKey: OWSAES256Key) -> Promise<Data> {
        let key = AvatarDownloadKey(avatarUrlPath: avatarUrlPath, profileKey: profileKey.keyData)
        let (promise, futureToStart): (Promise<Data>, Future<Data>?) = swiftValues.avatarDownloadRequests.update {
            if let existingPromise = $0[key] {
                return (existingPromise, nil)
            }
            let (promise, futureToStart) = Promise<Data>.pending()
            $0[key] = promise.ensure(on: DispatchQueue.global()) { [weak self] in
                self?.swiftValues.avatarDownloadRequests.update { _ = $0.removeValue(forKey: key) }
            }
            return (promise, futureToStart)
        }
        if let futureToStart {
            futureToStart.resolve(on: SyncScheduler(), with: Promise.wrapAsync {
                let backgroundTask = OWSBackgroundTask(label: "\(#function)")
                defer { backgroundTask.end() }

                return try await Self._downloadAndDecryptAvatar(
                    avatarUrlPath: avatarUrlPath,
                    profileKey: profileKey,
                    remainingRetries: 3
                )
            })
        }
        return promise
    }

    private static func _downloadAndDecryptAvatar(
        avatarUrlPath: String,
        profileKey: OWSAES256Key,
        remainingRetries: Int
    ) async throws -> Data {
        assert(!avatarUrlPath.isEmpty)
        do {
            Logger.info("")

            let urlSession = self.avatarUrlSession
            let response = try await urlSession.downloadTaskPromise(avatarUrlPath, method: .get).awaitable()

            let encryptedData: Data
            do {
                encryptedData = try Data(contentsOf: response.downloadUrl)
            } catch {
                owsFailDebug("Could not load data failed: \(error)")
                // Fail immediately; do not retry.
                throw SSKUnretryableError.couldNotLoadFileData
            }

            guard let decryptedData = OWSUserProfile.decrypt(profileData: encryptedData, profileKey: profileKey) else {
                throw OWSGenericError("Could not decrypt profile avatar.")
            }

            return decryptedData
        } catch where error.isNetworkFailureOrTimeout && remainingRetries > 0 {
            return try await _downloadAndDecryptAvatar(
                avatarUrlPath: avatarUrlPath,
                profileKey: profileKey,
                remainingRetries: remainingRetries - 1
            )
        }
    }
}
