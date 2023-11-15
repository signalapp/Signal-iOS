//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import SafariServices
import SignalMessaging

public extension ContactsViewHelper {

    func signalAccounts(includingLocalUser: Bool) -> [SignalAccount] {
        switch includingLocalUser {
        case true:
            return allSignalAccounts

        case false:
            let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
            return allSignalAccounts
                .filter { !($0.recipientAddress.isLocalAddress || $0.contact?.hasPhoneNumber(localNumber) == true) }
        }
    }
}

// MARK: - Updating Contacts

extension ContactsViewHelper {
    @objc
    func updateContacts() {
        AssertIsOnMainThread()
        owsAssertDebug(!CurrentAppContext().isNSE)

        let (systemContacts, signalConnections) = databaseStorage.read { tx in
            // All "System Contact"s that we believe are registered.
            let systemContacts = self.contactsManagerImpl.unsortedSignalAccounts(transaction: tx)

            // All Signal Connections that we believe are registered. In theory, this
            // should include your system contacts and the people you chat with.
            let signalConnections = self.profileManagerImpl.allWhitelistedRegisteredAddresses(tx: tx)
            return (systemContacts, signalConnections)
        }

        var signalAccounts = systemContacts
        var seenAddresses = Set(signalAccounts.lazy.map { $0.recipientAddress })
        for address in signalConnections {
            guard seenAddresses.insert(address).inserted else {
                // We prefer the copy from contactsManager which will appear first in
                // accountsToProcess; don't overwrite it.
                continue
            }
            signalAccounts.append(SignalAccount(address: address))
        }

        var phoneNumberMap = [String: SignalAccount]()
        var serviceIdMap = [ServiceIdObjC: SignalAccount]()

        for signalAccount in signalAccounts {
            if let phoneNumber = signalAccount.recipientPhoneNumber {
                phoneNumberMap[phoneNumber] = signalAccount
            }
            if let serviceId = signalAccount.recipientServiceIdObjc {
                serviceIdMap[serviceId] = signalAccount
            }
        }

        self.phoneNumberSignalAccountMap = phoneNumberMap
        self.serviceIdSignalAccountMap = serviceIdMap
        self.signalAccounts = self.contactsManagerImpl.sortSignalAccountsWithSneakyTransaction(signalAccounts)
        self.fireDidUpdateContacts()
    }

    private func fireDidUpdateContacts() {
        for delegate in observers.allObjects {
            delegate.contactsViewHelperDidUpdateContacts()
        }
    }
}

// MARK: - Presenting Permission-Gated Views

public extension ContactsViewHelper {

    private enum Constant {
        static let contactsAccessNotAllowedLearnMoreURL = URL(string: "https://support.signal.org/hc/articles/360007319011#ipad_contacts")!
    }

    private enum Purpose {
        case edit
        case share
        case invite
    }

    enum AuthorizedBehavior {
        case runAction(() -> Void)
        case pushViewController(on: UINavigationController, viewController: () -> UIViewController?)

    }

    private func perform(authorizedBehavior: AuthorizedBehavior) {
        switch authorizedBehavior {
        case .runAction(let authorizedBlock):
            authorizedBlock()
        case .pushViewController(on: let navigationController, viewController: let viewControllerBlock):
            guard let contactViewController = viewControllerBlock() else {
                return owsFailDebug("Missing contactViewController.")
            }
            navigationController.pushViewController(contactViewController, animated: true)
        }
    }

    enum UnauthorizedBehavior {
        case presentError(from: UIViewController)
    }

    private func performWhenDenied(unauthorizedBehavior: UnauthorizedBehavior, purpose: Purpose) {
        switch unauthorizedBehavior {
        case .presentError(from: let viewController):
            Self.presentContactAccessDeniedAlert(from: viewController, purpose: purpose)
        }
    }

    private func performWhenNotAllowed(unauthorizedBehavior: UnauthorizedBehavior) {
        switch unauthorizedBehavior {
        case .presentError(from: let viewController):
            Self.presentContactAccessNotAllowedAlert(from: viewController)
        }
    }

    func checkEditingAuthorization(authorizedBehavior: AuthorizedBehavior, unauthorizedBehavior: UnauthorizedBehavior) {
        AssertIsOnMainThread()

        switch contactsManagerImpl.editingAuthorization {
        case .notAllowed:
            performWhenNotAllowed(unauthorizedBehavior: unauthorizedBehavior)
        case .denied, .restricted:
            performWhenDenied(unauthorizedBehavior: unauthorizedBehavior, purpose: .edit)
        case .authorized:
            perform(authorizedBehavior: authorizedBehavior)
        }
    }

    enum SharingPurpose {
        case share
        case invite
    }

    func checkSharingAuthorization(
        purpose: SharingPurpose,
        authorizedBehavior: AuthorizedBehavior,
        unauthorizedBehavior: UnauthorizedBehavior
    ) {
        let deniedBlock = {
            let internalPurpose: Purpose
            switch purpose {
            case .share:
                internalPurpose = .share
            case .invite:
                internalPurpose = .invite
            }
            self.performWhenDenied(unauthorizedBehavior: unauthorizedBehavior, purpose: internalPurpose)
        }

        switch contactsManagerImpl.sharingAuthorization {
        case .notDetermined:
            CNContactStore().requestAccess(for: .contacts) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        self.perform(authorizedBehavior: authorizedBehavior)
                    } else {
                        deniedBlock()
                    }
                }
            }
        case .authorized:
            perform(authorizedBehavior: authorizedBehavior)
        case .denied:
            deniedBlock()
        }
    }

    private static func presentContactAccessDeniedAlert(from viewController: UIViewController, purpose: Purpose) {
        owsAssertDebug(!CurrentAppContext().isNSE)

        let title: String
        let message: String

        switch purpose {
        case .edit:
            title = OWSLocalizedString(
                "EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_TITLE",
                comment: "Alert title for when the user has just tried to edit a contacts after declining to give Signal contacts permissions"
            )
            message = OWSLocalizedString(
                "EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_BODY",
                comment: "Alert body for when the user has just tried to edit a contacts after declining to give Signal contacts permissions"
            )

        case .share:
            title = OWSLocalizedString(
                "CONTACT_SHARING_NO_ACCESS_TITLE",
                comment: "Alert title when contacts disabled while trying to share a contact."
            )
            message = OWSLocalizedString(
                "CONTACT_SHARING_NO_ACCESS_BODY",
                comment: "Alert body when contacts disabled while trying to share a contact."
            )

        case .invite:
            title = OWSLocalizedString(
                "INVITE_FLOW_REQUIRES_CONTACT_ACCESS_TITLE",
                comment: "Alert title when contacts disabled while trying to invite contacts to signal"
            )
            message = OWSLocalizedString(
                "INVITE_FLOW_REQUIRES_CONTACT_ACCESS_BODY",
                comment: "Alert body when contacts disabled while trying to invite contacts to signal"
            )
        }

        let actionSheet = ActionSheetController(title: title, message: message)

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "AB_PERMISSION_MISSING_ACTION_NOT_NOW",
                comment: "Button text to dismiss missing contacts permission alert"
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "ContactAccess", name: "not_now"),
            style: .cancel
        ))

        if let openSystemSettingsAction = AppContextUtils.openSystemSettingsAction(completion: nil) {
            actionSheet.addAction(openSystemSettingsAction)
        }

        viewController.presentActionSheet(actionSheet)
    }

    private static func presentContactAccessNotAllowedAlert(from viewController: UIViewController) {
        let actionSheet = ActionSheetController(
            message: OWSLocalizedString(
                "LINKED_DEVICE_CONTACTS_NOT_ALLOWED",
                comment: "Shown in an alert when trying to edit a contact."
            )
        )

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.learnMore) { [weak viewController] _ in
            guard let viewController else { return }
            presentContactAccessNotAllowedLearnMore(from: viewController)
        })

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton, style: .cancel))

        viewController.presentActionSheet(actionSheet)
    }

    static func presentContactAccessNotAllowedLearnMore(from viewController: UIViewController) {
        viewController.present(
            SFSafariViewController(url: Constant.contactsAccessNotAllowedLearnMoreURL),
            animated: true
        )
    }
}
