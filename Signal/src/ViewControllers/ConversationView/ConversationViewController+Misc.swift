//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import Foundation
import SignalMessaging

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

    func showUnblockConversationUI(completion: BlockActionCompletionBlock?) {
        self.userHasScrolled = false

        // To avoid "noisy" animations (hiding the keyboard before showing
        // the action sheet, re-showing it after), hide the keyboard before
        // showing the "unblock" action sheet.
        //
        // Unblocking is a rare interaction, so it's okay to leave the keyboard
        // hidden.
        dismissKeyBoard()

        BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self, completionBlock: completion)
    }

    // MARK: - Identity

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * returns YES if an alert was shown
     *          NO if there were no unconfirmed identities
     */
    func showSafetyNumberConfirmationIfNecessary(confirmationText: String,
                                                 completion: @escaping (Bool) -> Void) -> Bool {
        SafetyNumberConfirmationSheet.presentIfNecessary(addresses: thread.recipientAddressesWithSneakyTransaction,
                                                         confirmationText: confirmationText,
                                                         completion: completion)
    }

    // MARK: -

    func resendFailedOutgoingMessage(_ message: TSOutgoingMessage) {
        // If the message was remotely deleted, resend a *delete* message
        // rather than the message itself.
        let messageToSend = (message.wasRemotelyDeleted
                             ? databaseStorage.read { TSOutgoingDeleteMessage(thread: thread, message: message, transaction: $0) }
                             : message)

        let recipientsWithChangedSafetyNumber = message.failedRecipientAddresses(errorCode: UntrustedIdentityError.errorCode)
        if !recipientsWithChangedSafetyNumber.isEmpty {
            // Show special safety number change dialog
            let sheet = SafetyNumberConfirmationSheet(addressesToConfirm: recipientsWithChangedSafetyNumber,
                                                      confirmationText: MessageStrings.sendButton) { didConfirm in
                if didConfirm {
                    Self.databaseStorage.asyncWrite { transaction in
                        Self.sskJobQueues.messageSenderJobQueue.add(
                            message: messageToSend.asPreparer,
                            transaction: transaction
                        )
                    }
                }
            }
            self.present(sheet, animated: true, completion: nil)
            return
        }

        let actionSheet = ActionSheetController(title: nil,
                                                message: message.mostRecentFailureText)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.deleteForMeButton,
                                                style: .destructive) { _ in
            Self.databaseStorage.write { transaction in
                message.anyRemove(transaction: transaction)
            }
        })

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("SEND_AGAIN_BUTTON", comment: ""),
                                                accessibilityIdentifier: "send_again",
                                                style: .default) { _ in
            Self.databaseStorage.asyncWrite { transaction in
                Self.sskJobQueues.messageSenderJobQueue.add(
                    message: messageToSend.asPreparer,
                    transaction: transaction
                )
            }
        })

        dismissKeyBoard()
        self.presentActionSheet(actionSheet)
    }

    // MARK: - Verification

    // Returns a random sub-collection of the group members who are "no longer verified".
    func arbitraryNoLongerVerifiedAddresses(limit: Int) -> [SignalServiceAddress] {
        databaseStorage.read { transaction in
            self.noLongerVerifiedAddresses(limit: limit, transaction: transaction)
        }
    }

    func noLongerVerifiedAddresses(limit: Int, transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        if let groupThread = thread as? TSGroupThread {
            return Self.identityManager.noLongerVerifiedAddresses(inGroup: groupThread.uniqueId,
                                                                  limit: limit,
                                                                  transaction: transaction)
        }
        return thread.recipientAddresses(with: transaction).filter { address in
            Self.identityManager.verificationState(for: address,
                                                   transaction: transaction) == .noLongerVerified
        }
    }

    func resetVerificationStateToDefault() {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            let noLongerVerifiedAddresses = self.noLongerVerifiedAddresses(limit: Int.max,
                                                                           transaction: transaction)
            for address in noLongerVerifiedAddresses {
                owsAssertDebug(address.isValid)

                guard let recipientIdentity = Self.identityManager.recipientIdentity(for: address,
                                                                                     transaction: transaction) else {
                    owsFailDebug("Missing recipientIdentity.")
                    continue
                }
                guard recipientIdentity.identityKey.count > 0 else {
                    owsFailDebug("Invalid identityKey.")
                    continue
                }
                Self.identityManager.setVerificationState(
                    .default,
                    identityKey: recipientIdentity.identityKey,
                    address: address,
                    isUserInitiatedChange: true,
                    transaction: transaction
                )
            }
        }
    }

    func showNoLongerVerifiedUI() {
        AssertIsOnMainThread()

        let addresses = arbitraryNoLongerVerifiedAddresses(limit: 2)
        switch addresses.count {
        case 0:
             break

        case 1:
            // Pick one in an arbitrary but deterministic manner.
            showFingerprint(address: addresses[0])

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
            spoilerReveal: viewState.spoilerReveal
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
                spoilerReveal: viewState.spoilerReveal,
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

        let actionSheet = MemberActionSheet(address: address, groupViewHelper: groupViewHelper)
        actionSheet.present(from: self)
    }
}

// MARK: -

extension ConversationViewController: ConversationSettingsViewDelegate {

    public func conversationColorWasUpdated() {
        AssertIsOnMainThread()

        updateConversationStyle()
        headerView.updateAvatar()
    }

    public func conversationSettingsDidUpdate() {
        AssertIsOnMainThread()

        Self.databaseStorage.write { transaction in
            // We updated the group, so if there was a pending message request we should accept it.
            ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer(thread: self.thread,
                                                                                            transaction: transaction)
        }
    }

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

    public func popAllConversationSettingsViews(completion: (() -> Void)?) {
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

// MARK: - Unread Counts

public extension ConversationViewController {
    var unreadMessageCount: UInt {
        get { viewState.unreadMessageCount }
        set {
            guard viewState.unreadMessageCount != newValue else {
                return
            }
            viewState.unreadMessageCount = newValue
            configureScrollDownButtons()
        }
    }

    var unreadMentionMessages: [TSMessage] {
        get { viewState.unreadMentionMessages }
        set {
            guard viewState.unreadMentionMessages != newValue else {
                return
            }
            viewState.unreadMentionMessages = newValue
            configureScrollDownButtons()
        }
    }

    func updateUnreadMessageFlagUsingAsyncTransaction() {
        // Resubmits to the main queue because we can't verify we're not already in a transaction we don't know about.
        // This method may be called in response to all sorts of view state changes, e.g. scroll state. These changes
        // can be a result of a UIKit response to app activity that already has an open transaction.
        //
        // We need a transaction to proceed, but we can't verify that we're not already in one (unless explicitly handed
        // one) To workaround this, we async a block to open a fresh transaction on the main queue.
        DispatchQueue.main.async {
            Self.databaseStorage.read { transaction in
                self.updateUnreadMessageFlag(transaction: transaction)
            }
        }
    }

    func updateUnreadMessageFlag(transaction: SDSAnyReadTransaction) {
        AssertIsOnMainThread()

        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
        let unreadCount = interactionFinder.unreadCount(transaction: transaction.unwrapGrdbRead)
        self.unreadMessageCount = unreadCount

        if let localAddress = tsAccountManager.localAddress {
            self.unreadMentionMessages = MentionFinder.messagesMentioning(address: localAddress,
                                                                          in: thread,
                                                                          includeReadMessages: false,
                                                                          transaction: transaction.unwrapGrdbRead)
        } else {
            owsFailDebug("Missing localAddress.")
        }
    }

    /// Checks to see if the unread message flag can be cleared. Shortcircuits if the flag is not set to begin with
    func clearUnreadMessageFlagIfNecessary() {
        AssertIsOnMainThread()

        if unreadMessageCount > 0 {
            updateUnreadMessageFlagUsingAsyncTransaction()
        }
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
        if OWSWindowManager.shared.shouldShowCallView {
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
            clearUnreadMessageFlagIfNecessary()

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
