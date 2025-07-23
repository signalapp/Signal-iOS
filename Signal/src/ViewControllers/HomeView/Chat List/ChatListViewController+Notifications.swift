//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI

extension ChatListViewController {

    public static let clearSearch = Notification.Name("clearSearch")

    public func observeNotifications() {
        AssertIsOnMainThread()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(signalAccountsDidChange),
                                               name: .OWSContactsManagerSignalAccountsDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillResignActive),
                                               name: .OWSApplicationWillResignActive,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(outageStateDidChange),
                                               name: OutageDetection.outageStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(localProfileDidChange),
                                               name: UserProfileNotifications.localProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(profileWhitelistDidChange),
                                               name: UserProfileNotifications.profileWhitelistDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherProfileDidChange(_:)),
                                               name: UserProfileNotifications.otherUsersProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appExpiryDidChange),
                                               name: AppExpiry.AppExpiryDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(significantTimeChangeNotification),
                                               name: UIApplication.significantTimeChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(preferContactAvatarsPreferenceDidChange),
                                               name: SSKPreferences.preferContactAvatarsPreferenceDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(blockListDidChange),
                                               name: BlockingManager.blockListDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(clearSearch),
                                               name: ChatListViewController.clearSearch,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(clearSearch),
                                               name: ReactionManager.localUserReacted,
                                               object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localUsernameStateDidChange),
            name: Usernames.localUsernameStateChangedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backupAttachmentDownloadQueueStatusDidChange(_:)),
            name: .backupAttachmentDownloadQueueStatusDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backupPlanDidChange(_:)),
            name: .backupPlanChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadExperienceUpgrades),
            name: .inactivePrimaryDeviceChanged,
            object: nil
        )

        viewState.backupDownloadProgressViewState.downloadQueueStatus =
            DependenciesBridge.shared.backupAttachmentDownloadQueueStatusReporter.currentStatus()
        Task { @MainActor in
            self.viewState.backupDownloadProgressViewState.downloadProgressObserver = await DependenciesBridge.shared
                .backupAttachmentDownloadProgress
                .addObserver { [weak self] progress in
                    DispatchQueue.main.asyncIfNecessary {
                        guard let self else { return }
                        self.viewState.backupDownloadProgressViewState.downloadProgress = progress
                        self.viewState.backupDownloadProgressView.update(viewState: self.viewState.backupDownloadProgressViewState)
                    }
                }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showFYISheetIfNecessary),
            name: DonationReceiptCredentialRedemptionJob.didSucceedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showFYISheetIfNecessary),
            name: DonationReceiptCredentialRedemptionJob.didFailNotification,
            object: nil
        )

        SUIEnvironment.shared.contactsViewHelperRef.addObserver(self)

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    // MARK: -

    @objc
    private func preferContactAvatarsPreferenceDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        reloadTableDataAndResetCellContentCache()
    }

    @objc
    private func signalAccountsDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        // This is wasteful but this event is very rare.
        reloadTableDataAndResetThreadViewModelCache()
    }

    @objc
    private func registrationStateDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateRegistrationReminderView()
        loadCoordinator.loadIfNecessary()
    }

    @objc
    private func outageStateDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateOutageDetectionReminderView()
        loadCoordinator.loadIfNecessary()
    }

    @objc
    private func localProfileDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        showFYISheetIfNecessary()
    }

    @objc
    private func appExpiryDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateExpirationReminderView()
        loadCoordinator.loadIfNecessary()
    }

    @objc
    private func significantTimeChangeNotification(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateExpirationReminderView()
        loadCoordinator.loadIfNecessary()
    }

    @objc
    private func applicationWillEnterForeground(_ notification: NSNotification) {
        AssertIsOnMainThread()

        loadCoordinator.applicationWillEnterForeground()
    }

    @objc
    private func applicationDidBecomeActive(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateShouldBeUpdatingView()

        if !ExperienceUpgradeManager.presentNext(fromViewController: self) {
            presentGetStartedBannerIfNecessary()
        }
    }

    @objc
    private func applicationWillResignActive(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateShouldBeUpdatingView()
    }

    @objc
    private func profileWhitelistDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        // If profile whitelist just changed, we need to update the associated
        // thread to reflect the latest message request state.
        let address: SignalServiceAddress? = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress
        let groupId: Data? = notification.userInfo?[UserProfileNotifications.profileGroupIdKey] as? Data

        let changedThreadId: String? = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            if let address = address,
               address.isValid {
                return TSContactThread.getWithContactAddress(address, transaction: transaction)?.uniqueId
            } else if let groupId = groupId {
                return TSGroupThread.threadId(forGroupId: groupId, transaction: transaction)
            } else {
                return nil
            }
        }

        if let threadId = changedThreadId {
            self.loadCoordinator.scheduleLoad(updatedThreadIds: Set([threadId]))
        }
    }

    @objc
    private func otherProfileDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        let address = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress

        let changedThreadId: String? = SSKEnvironment.shared.databaseStorageRef.read { readTx in
            if let address = address, address.isValid {
                return TSContactThread.getWithContactAddress(address, transaction: readTx)?.uniqueId
            } else {
                return nil
            }
        }

        if let changedThreadId = changedThreadId {
            self.loadCoordinator.scheduleLoad(updatedThreadIds: Set([changedThreadId]))
        }
    }

    @objc
    private func blockListDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        // This is wasteful but this event is very rare.
        reloadTableDataAndResetCellContentCache()
    }

    @objc
    private func clearSearch(_ notification: NSNotification) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) { [weak self] in
            if let self = self {
                self.searchBar.delegate?.searchBarCancelButtonClicked?(self.searchBar)
            }
        }
    }

    @objc
    private func localUsernameStateDidChange() {
        updateUsernameReminderView()
        loadCoordinator.loadIfNecessary()
    }

    @objc
    private func backupAttachmentDownloadQueueStatusDidChange(_ notification: Notification) {
        self.viewState.backupDownloadProgressViewState.downloadQueueStatus =
            DependenciesBridge.shared.backupAttachmentDownloadQueueStatusReporter.currentStatus()
        self.viewState.backupDownloadProgressView.update(viewState: self.viewState.backupDownloadProgressViewState)
    }

    @objc
    private func backupPlanDidChange(_ notification: Notification) {
        let db = DependenciesBridge.shared.db
        db.read { viewState.backupDownloadProgressViewState.refetchDBState(tx: $0) }
        viewState.backupDownloadProgressView.update(viewState: viewState.backupDownloadProgressViewState)
    }

    @objc
    private func reloadExperienceUpgrades() {
        AssertIsOnMainThread()

        _ = ExperienceUpgradeManager.presentNext(fromViewController: self)
    }
}

// MARK: - Notifications

extension ChatListViewController: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdate(tableName: TSPaymentModel.table.tableName) {
            updateUnreadPaymentNotificationsCountWithSneakyTransaction()
        }

        if !databaseChanges.threadUniqueIdsForChatListUpdate.isEmpty {
            self.loadCoordinator.scheduleLoad(updatedThreadIds: databaseChanges.threadUniqueIdsForChatListUpdate)
        }
    }

    public func databaseChangesDidUpdateExternally() {
        // External database modifications can't be converted into incremental updates,
        // so rebuild everything.  This is expensive and usually isn't necessary, but
        // there's no alternative.
        self.loadCoordinator.scheduleHardReset()
    }

    public func databaseChangesDidReset() {
        // This should only happen if we need to recover from an error in the
        // database change observation pipeline.  This should never occur,
        // but when it does we need to rebuild everything.  This is expensive,
        // but there's no alternative.
        self.loadCoordinator.scheduleHardReset()
    }
}

extension ChatListViewController: ContactsViewHelperObserver {
    public func contactsViewHelperDidUpdateContacts() {
        if !firstConversationCueView.isHidden {
            updateFirstConversationLabel()
        }
    }
}
