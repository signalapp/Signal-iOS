//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import SignalServiceKit
import SignalMessaging
import SignalUI

public extension ConversationViewController {

    func updateV2GroupIfNecessary() {
        AssertIsOnMainThread()

        guard let groupThread = thread as? TSGroupThread,
              thread.isGroupV2Thread else {
            return
        }
        // Try to update the v2 group to latest from the service.
        // This will help keep us in sync if we've missed any group updates, etc.
        groupV2UpdatesObjc.tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(groupThread)
    }

    func showUnblockConversationUI(completion: BlockListUIUtils.Completion?) {
        self.userHasScrolled = false

        // To avoid "noisy" animations (hiding the keyboard before showing
        // the action sheet, re-showing it after), hide the keyboard before
        // showing the "unblock" action sheet.
        //
        // Unblocking is a rare interaction, so it's okay to leave the keyboard
        // hidden.
        dismissKeyBoard()

        BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self, completion: completion)
    }

    // MARK: - Identity

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * returns YES if an alert was shown
     *          NO if there were no unconfirmed identities
     */
    func showSafetyNumberConfirmationIfNecessary(
        confirmationText: String,
        untrustedThreshold: Date?,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        SafetyNumberConfirmationSheet.presentIfNecessary(
            addresses: thread.recipientAddressesWithSneakyTransaction,
            confirmationText: confirmationText,
            untrustedThreshold: untrustedThreshold,
            completion: completion
        )
    }

    // MARK: - Verification

    func noLongerVerifiedIdentityKeys(tx: SDSAnyReadTransaction) -> [SignalServiceAddress: Data] {
        if let groupThread = thread as? TSGroupThread {
            return OWSRecipientIdentity.noLongerVerifiedIdentityKeys(in: groupThread.uniqueId, tx: tx)
        }
        let identityManager = DependenciesBridge.shared.identityManager
        return thread.recipientAddresses(with: tx).reduce(into: [:]) { result, address in
            guard let recipientIdentity = identityManager.recipientIdentity(for: address, tx: tx.asV2Read) else {
                return
            }
            guard recipientIdentity.verificationState == .noLongerVerified else {
                return
            }
            result[address] = recipientIdentity.identityKey
        }
    }

    func resetVerificationStateToDefault(noLongerVerifiedIdentityKeys: [SignalServiceAddress: Data]) {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            let identityManager = DependenciesBridge.shared.identityManager
            for (address, identityKey) in noLongerVerifiedIdentityKeys {
                owsAssertDebug(address.isValid)
                _ = identityManager.setVerificationState(
                    .implicit(isAcknowledged: true),
                    of: identityKey,
                    for: address,
                    isUserInitiatedChange: true,
                    tx: transaction.asV2Write
                )
            }
        }
    }

    func showNoLongerVerifiedUI(noLongerVerifiedIdentityKeys: [SignalServiceAddress: Data]) {
        AssertIsOnMainThread()

        switch noLongerVerifiedIdentityKeys.count {
        case 0:
             break

        case 1:
            showFingerprint(address: noLongerVerifiedIdentityKeys.first!.key)

        default:
            showConversationSettingsAndShowVerification()
        }
    }

    // MARK: - Toast

    func presentToastCVC(_ toastText: String) {
        let toastController = ToastController(text: toastText)
        let kToastInset: CGFloat = 10
        let bottomInset = kToastInset + collectionView.contentInset.bottom + view.layoutMargins.bottom
        toastController.presentToastView(from: .bottom, of: self.view, inset: bottomInset)
    }

    func presentMissingQuotedReplyToast() {
        Logger.info("")

        let toastText = OWSLocalizedString("QUOTED_REPLY_ORIGINAL_MESSAGE_DELETED",
                                          comment: "Toast alert text shown when tapping on a quoted message which we cannot scroll to because the local copy of the message was since deleted.")
        presentToastCVC(toastText)
    }

    func presentRemotelySourcedQuotedReplyToast() {
        Logger.info("")

        let toastText = OWSLocalizedString("QUOTED_REPLY_ORIGINAL_MESSAGE_REMOTELY_SOURCED",
                                          comment: "Toast alert text shown when tapping on a quoted message which we cannot scroll to because the local copy of the message didn't exist when the quote was received.")
        presentToastCVC(toastText)
    }

    func presentViewOnceAlreadyViewedToast() {
        Logger.info("")

        let toastText = OWSLocalizedString("VIEW_ONCE_ALREADY_VIEWED_TOAST",
                                          comment: "Toast alert text shown when tapping on a view-once message that has already been viewed.")
        presentToastCVC(toastText)
    }

    func presentViewOnceOutgoingToast() {
        Logger.info("")

        let toastText = OWSLocalizedString("VIEW_ONCE_OUTGOING_TOAST",
                                          comment: "Toast alert text shown when tapping on a view-once message that you have sent.")
        presentToastCVC(toastText)
    }

    // MARK: - Conversation Settings

    func showConversationSettings() {
        showConversationSettings(mode: .default)
    }

    func showConversationSettingsAndShowAllMedia() {
        showConversationSettings(mode: .showAllMedia)
    }

    func showConversationSettingsAndShowVerification() {
        showConversationSettings(mode: .showVerification)
    }

    func showConversationSettingsAndShowMemberRequests() {
        showConversationSettings(mode: .showMemberRequests)
    }

    func showConversationSettings(mode: ConversationSettingsPresentationMode) {
        guard let viewControllersUpToSelf = self.viewControllersUpToSelf else {
            return
        }
        var viewControllers = viewControllersUpToSelf

        let settingsView = ConversationSettingsViewController(
            threadViewModel: threadViewModel,
            spoilerState: viewState.spoilerState
        )
        settingsView.conversationSettingsViewDelegate = self
        viewControllers.append(settingsView)

        switch mode {
        case .default:
            break
        case .showVerification:
            settingsView.showVerificationOnAppear = true
        case .showMemberRequests:
            if let view = settingsView.buildMemberRequestsAndInvitesView() {
                viewControllers.append(view)
            }
        case .showAllMedia:
            viewControllers.append(AllMediaViewController(
                thread: thread,
                spoilerState: viewState.spoilerState,
                name: title
            ))
        }

        navigationController?.setViewControllers(viewControllers, animated: true)
    }

    private var viewControllersUpToSelf: [UIViewController]? {
        AssertIsOnMainThread()

        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return nil
        }

        if navigationController.topViewController == self {
            return navigationController.viewControllers
        }

        let viewControllers = navigationController.viewControllers
        guard let index = viewControllers.firstIndex(of: self) else {
            owsFailDebug("Unexpectedly missing from view hierarchy")
            return viewControllers
        }

        return Array(viewControllers.prefix(upTo: index + 1))
    }

    // MARK: - Member Action Sheet

    func showMemberActionSheet(forAddress address: SignalServiceAddress, withHapticFeedback: Bool) {
        AssertIsOnMainThread()

        if withHapticFeedback {
            ImpactHapticFeedback.impactOccurred(style: .light)
        }

        var groupViewHelper: GroupViewHelper?
        if threadViewModel.isGroupThread {
            groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
            groupViewHelper!.delegate = self
        }

        let actionSheet = MemberActionSheet(address: address, groupViewHelper: groupViewHelper, spoilerState: spoilerState)
        actionSheet.present(from: self)
    }
}

// MARK: -

extension ConversationViewController: ConversationSettingsViewDelegate {

    public func conversationSettingsDidRequestConversationSearch() {
        AssertIsOnMainThread()

        self.uiMode = .search

        self.popAllConversationSettingsViews {
            // This delay is unfortunate, but without it, self.searchController.uiSearchController.searchBar
            // isn't yet ready to become first responder. Presumably we're still mid transition.
            // A hardcorded constant like this isn't great because it's either too slow, making our users
            // wait, or too fast, and fails to wait long enough to be ready to become first responder.
            // Luckily in this case the stakes aren't catastrophic. In the case that we're too aggressive
            // the user will just have to manually tap into the search field before typing.

            // Leaving this assert in as proof that we're not ready to become first responder yet.
            // If this assert fails, *great* maybe we can get rid of this delay.
            owsAssertDebug(!self.searchController.uiSearchController.searchBar.canBecomeFirstResponder)

            // We wait N seconds for it to become ready.
            let initialDelay: TimeInterval = 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
                self?.tryToBecomeFirstResponderForSearch(cumulativeDelay: initialDelay)
            }
        }
    }

    private func popAllConversationSettingsViews(completion: (() -> Void)?) {
        AssertIsOnMainThread()

        guard let presentedViewController = presentedViewController else {
            navigationController?.popToViewController(self, animated: true, completion: completion)
            return
        }
        presentedViewController.dismiss(animated: true) {
            self.navigationController?.popToViewController(self, animated: true, completion: completion)
        }
    }

    // MARK: - Conversation Search

    private func tryToBecomeFirstResponderForSearch(cumulativeDelay: TimeInterval) {
        // If this took more than N seconds, assume we're not going
        // to be able to present search and bail.
        if cumulativeDelay >= 1.5 {
            owsFailDebug("Giving up presenting search after excessive retry attempts.")
            self.uiMode = .normal
            return
        }

        // Sometimes it takes longer, so we'll keep retrying..
        if !searchController.uiSearchController.searchBar.canBecomeFirstResponder {
            let additionalDelay: TimeInterval = 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + additionalDelay) { [weak self] in
                self?.tryToBecomeFirstResponderForSearch(cumulativeDelay: cumulativeDelay + additionalDelay)
            }
            return
        }

        Logger.verbose("Search controller became ready after \(cumulativeDelay) seconds")
        searchController.uiSearchController.searchBar.becomeFirstResponder()
    }
}

// MARK: -

extension ConversationViewController: CNContactViewControllerDelegate {
    public func contactViewController(_ viewController: CNContactViewController,
                                      didCompleteWith contact: CNContact?) {
        navigationController?.popToViewController(self, animated: true)
    }
}

// MARK: - Preview / 3D Touch / UIContextMenu Methods

public extension ConversationViewController {
    var isInPreviewPlatter: Bool {
        get { viewState.isInPreviewPlatter }
        set {
            guard viewState.isInPreviewPlatter != newValue else {
                return
            }
            viewState.isInPreviewPlatter = newValue
            if hasViewWillAppearEverBegun {
                ensureBottomViewType()
            }
            configureScrollDownButtons()
        }
    }

    @objc
    func previewSetup() {
        isInPreviewPlatter = true
        actionOnOpen = .none
    }
}

// MARK: - Timers

extension ConversationViewController {
    public func startReadTimer() {
        AssertIsOnMainThread()

        readTimer?.invalidate()
        let readTimer = Timer.weakTimer(withTimeInterval: 0.1,
                                        target: self,
                                        selector: #selector(readTimerDidFire),
                                        userInfo: nil,
                                        repeats: true)
        self.readTimer = readTimer
        RunLoop.main.add(readTimer, forMode: .common)
    }

    @objc
    private func readTimerDidFire() {
        AssertIsOnMainThread()

        if layout.isPerformBatchUpdatesOrReloadDataBeingApplied {
            return
        }
        markVisibleMessagesAsRead()
    }

    public func cancelReadTimer() {
        AssertIsOnMainThread()

        readTimer?.invalidate()
        self.readTimer = nil
    }

    private var readTimer: Timer? {
        get { viewState.readTimer }
        set { viewState.readTimer = newValue }
    }

    public var reloadTimer: Timer? {
        get { viewState.reloadTimer }
        set { viewState.reloadTimer = newValue }
    }

    func startReloadTimer() {
        AssertIsOnMainThread()
        let reloadTimer = Timer.weakTimer(withTimeInterval: 1.0,
                                          target: self,
                                          selector: #selector(reloadTimerDidFire),
                                          userInfo: nil,
                                          repeats: true)
        self.reloadTimer = reloadTimer
        RunLoop.main.add(reloadTimer, forMode: .common)
    }

    @objc
    private func reloadTimerDidFire() {
        AssertIsOnMainThread()

        if isUserScrolling || !isViewCompletelyAppeared || !isViewVisible
            || !CurrentAppContext().isAppForegroundAndActive() || !viewHasEverAppeared {
            return
        }

        let timeSinceLastReload = abs(self.lastReloadDate.timeIntervalSinceNow)
        let kReloadFrequency: TimeInterval = 60
        if timeSinceLastReload < kReloadFrequency {
            return
        }

        Logger.verbose("reloading conversation view contents.")

        // Auto-load more if necessary...
        if !autoLoadMoreIfNecessary() {
            // ...Otherwise, reload everything.
            //
            // TODO: We could make this cheaper by using enqueueReload()
            // if we moved volatile profile / footer state to the view state.
            loadCoordinator.enqueueReload()
        }
    }

    var lastSortIdMarkedRead: UInt64 {
        get { viewState.lastSortIdMarkedRead }
        set { viewState.lastSortIdMarkedRead = newValue }
    }

    var isMarkingAsRead: Bool {
        get { viewState.isMarkingAsRead }
        set { viewState.isMarkingAsRead = newValue }
    }

    private func setLastSortIdMarkedRead(lastSortIdMarkedRead: UInt64) {
        AssertIsOnMainThread()
        owsAssertDebug(self.isMarkingAsRead)

        self.lastSortIdMarkedRead = lastSortIdMarkedRead
    }

    public func markVisibleMessagesAsRead() {
        AssertIsOnMainThread()

        if nil != self.presentedViewController {
            return
        }
        if WindowManager.shared.shouldShowCallView {
            return
        }
        if navigationController?.topViewController != self {
            return
        }

        // Always clear the thread unread flag
        clearThreadUnreadFlagIfNecessary()

        let lastVisibleSortId = self.lastVisibleSortId
        let isShowingUnreadMessage = lastVisibleSortId > self.lastSortIdMarkedRead
        if !self.isMarkingAsRead && isShowingUnreadMessage {
            self.isMarkingAsRead = true

            BenchManager.benchAsync(title: "marking as read") { benchCompletion in
                Self.receiptManager.markAsReadLocally(beforeSortId: lastVisibleSortId,
                                                      thread: self.thread,
                                                      hasPendingMessageRequest: self.threadViewModel.hasPendingMessageRequest) {
                    AssertIsOnMainThread()
                    self.setLastSortIdMarkedRead(lastSortIdMarkedRead: lastVisibleSortId)
                    self.isMarkingAsRead = false

                    // If -markVisibleMessagesAsRead wasn't invoked on a
                    // timer, we'd want to double check that the current
                    // -lastVisibleSortId hasn't incremented since we
                    // started the read receipt request. But we have a
                    // timer, so if it has changed, this method will just
                    // be reinvoked in < 100ms.

                    benchCompletion()
                }
            }
        }
    }
}
