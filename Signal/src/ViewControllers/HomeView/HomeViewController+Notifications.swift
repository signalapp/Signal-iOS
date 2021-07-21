//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension HomeViewController {

    @objc
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
                                               name: .localProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(profileWhitelistDidChange),
                                               name: .profileWhitelistDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appExpiryDidChange),
                                               name: AppExpiry.AppExpiryDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(preferContactAvatarsPreferenceDidChange),
                                               name: SSKPreferences.preferContactAvatarsPreferenceDidChange,
                                               object: nil)

        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    // MARK: -

    @objc
    private func preferContactAvatarsPreferenceDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateAvatars()
    }

    @objc
    private func signalAccountsDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        reloadTableViewData()

        if !firstConversationCueView.isHidden {
            updateFirstConversationLabel()
        }
    }

    @objc
    private func registrationStateDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateReminderViews()
    }

    @objc
    private func outageStateDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateReminderViews()
    }

    @objc
    private func localProfileDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateBarButtonItems()
    }

    @objc
    private func appExpiryDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateReminderViews()
    }

    @objc
    private func applicationWillEnterForeground(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateViewState()
    }

    @objc
    private func applicationDidBecomeActive(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateShouldObserveDBModifications()

        if !ExperienceUpgradeManager.presentNext(fromViewController: self) {
            OWSActionSheets.showIOSUpgradeNagIfNecessary()
            presentGetStartedBannerIfNecessary()
        }
    }

    @objc
    private func applicationWillResignActive(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateShouldObserveDBModifications()
    }

    @objc
    private func profileWhitelistDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        // If profile whitelist just changed, we need to update the associated
        // thread to reflect the latest message request state.
        let address: SignalServiceAddress? = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress
        let groupId: Data? = notification.userInfo?[kNSNotificationKey_ProfileGroupId] as? Data

        let changedThreadId: String? = databaseStorage.read { transaction in
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
            updateRenderStateWithDiff(updatedThreadIds: Set<String>([threadId]))
        }
    }
}

// MARK: - Notifications

extension HomeViewController: DatabaseChangeDelegate {
    public func databaseChangesWillUpdate() {
        AssertIsOnMainThread()

        BenchManager.startEvent(title: "uiDatabaseUpdate", eventId: "uiDatabaseUpdate")
    }

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()

        if databaseChanges.didUpdateModel(collection: TSPaymentModel.collection()) {
            updateUnreadPaymentNotificationsCountWithSneakyTransaction()
        }

        guard shouldObserveDBModifications else {
            return
        }

        updateRenderStateWithDiff(updatedThreadIds: databaseChanges.threadUniqueIds)
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()

        Logger.verbose("")

        if shouldObserveDBModifications {
            // External database modifications can't be converted into incremental updates,
            // so rebuild everything.  This is expensive and usually isn't necessary, but
            // there's no alternative.
            //
            // We don't need to do this if we're not observing db modifications since we'll
            // do it when we resume.
            resetMappings()
        }
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()

        if shouldObserveDBModifications {
            // We don't need to do this if we're not observing db modifications since we'll
            // do it when we resume.
            resetMappings()
        }
    }
}
