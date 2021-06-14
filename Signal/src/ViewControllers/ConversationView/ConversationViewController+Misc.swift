//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import ContactsUI

@objc
public extension ConversationViewController {

    func showUnblockConversationUI(completionBlock: BlockActionCompletionBlock?) {
        self.userHasScrolled = false

        // To avoid "noisy" animations (hiding the keyboard before showing
        // the action sheet, re-showing it after), hide the keyboard before
        // showing the "unblock" action sheet.
        //
        // Unblocking is a rare interaction, so it's okay to leave the keyboard
        // hidden.
        dismissKeyBoard()

        BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self, completionBlock: completionBlock)
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
        SafetyNumberConfirmationSheet.presentIfNecessary(addresses: thread.recipientAddresses,
                                                         confirmationText: confirmationText,
                                                         completion: completion)
    }

    // MARK: -

    func resendFailedOutgoingMessage(_ message: TSOutgoingMessage) {
        // If the message was remotely deleted, resend a *delete* message
        // rather than the message itself.
        let messageToSend = (message.wasRemotelyDeleted
                                ? TSOutgoingDeleteMessage(thread: thread, message: message)
                                : message)

        let recipientsWithChangedSafetyNumber = message.failedRecipientAddresses(errorCode: .untrustedIdentity)
        if !recipientsWithChangedSafetyNumber.isEmpty {
            // Show special safety number change dialog
            let sheet = SafetyNumberConfirmationSheet(addressesToConfirm: recipientsWithChangedSafetyNumber,
                                                      confirmationText: MessageStrings.sendButton) { didConfirm in
                if didConfirm {
                    Self.databaseStorage.asyncWrite { transaction in
                        Self.messageSenderJobQueue.add(message: messageToSend.asPreparer,
                                                       transaction: transaction)
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

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("SEND_AGAIN_BUTTON", comment: ""),
                                                accessibilityIdentifier: "send_again",
                                                style: .default) { _ in
            Self.databaseStorage.asyncWrite { transaction in
                Self.messageSenderJobQueue.add(message: messageToSend.asPreparer,
                                               transaction: transaction)
            }
        })

        dismissKeyBoard()
        self.presentActionSheet(actionSheet)
    }

    // MARK: - Toast

    func presentToastCVC(_ toastText: String) {
        let toastController = ToastController(text: toastText)
        let kToastInset: CGFloat = 10
        let bottomInset = kToastInset + collectionView.contentInset.bottom + view.layoutMargins.bottom
        toastController.presentToastView(fromBottomOfView: self.view, inset: bottomInset)
    }

    func presentMissingQuotedReplyToast() {
        Logger.info("")

        let toastText = NSLocalizedString("QUOTED_REPLY_ORIGINAL_MESSAGE_DELETED",
                                          comment: "Toast alert text shown when tapping on a quoted message which we cannot scroll to because the local copy of the message was since deleted.")
        presentToastCVC(toastText)
    }

    func presentRemotelySourcedQuotedReplyToast() {
        Logger.info("")

        let toastText = NSLocalizedString("QUOTED_REPLY_ORIGINAL_MESSAGE_REMOTELY_SOURCED",
                                          comment: "Toast alert text shown when tapping on a quoted message which we cannot scroll to because the local copy of the message didn't exist when the quote was received.")
        presentToastCVC(toastText)
    }

    func presentViewOnceAlreadyViewedToast() {
        Logger.info("")

        let toastText = NSLocalizedString("VIEW_ONCE_ALREADY_VIEWED_TOAST",
                                          comment: "Toast alert text shown when tapping on a view-once message that has already been viewed.")
        presentToastCVC(toastText)
    }

    func presentViewOnceOutgoingToast() {
        Logger.info("")

        let toastText = NSLocalizedString("VIEW_ONCE_OUTGOING_TOAST",
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

        let settingsView = ConversationSettingsViewController(threadViewModel: threadViewModel)
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
            viewControllers.append(MediaTileViewController(thread: thread))
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
}

// MARK: -

extension ConversationViewController: ConversationSettingsViewDelegate {

    @objc
    public func conversationColorWasUpdated() {
        AssertIsOnMainThread()

        updateConversationStyle()
        headerView.updateAvatar()
    }

    @objc
    public func conversationSettingsDidUpdate() {
        AssertIsOnMainThread()

        Self.databaseStorage.write { transaction in
            // We updated the group, so if there was a pending message request we should accept it.
            ThreadUtil.addThread(toProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer: self.thread,
                                 transaction: transaction)
        }
    }

    @objc
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

    @objc
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

    @objc
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
    @objc
    public func contactViewController(_ viewController: CNContactViewController,
                                      didCompleteWith contact: CNContact?) {
        navigationController?.popToViewController(self, animated: true)
    }
}
