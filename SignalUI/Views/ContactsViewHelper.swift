//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation

@objc
public extension ContactsViewHelper {
    @objc(signalAccountsIncludingLocalUser:)
    func signalAccounts(includingLocalUser: Bool) -> [SignalAccount] {
        guard !includingLocalUser else {
            return allSignalAccounts
        }
        guard let localNumber = TSAccountManager.localNumber else {
            return allSignalAccounts
        }
        return allSignalAccounts.filter { signalAccount in
            if signalAccount.recipientAddress.isLocalAddress {
                return false
            }
            if let contact = signalAccount.contact {
                for phoneNumber in contact.parsedPhoneNumbers {
                    if phoneNumber.toE164() == localNumber {
                        return false
                    }
                }
            }
            return true
        }
    }
}

// MARK: - Presenting Permission-Gated Views

public extension ContactsViewHelper {

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

    private func perform(unauthorizedBehavior: UnauthorizedBehavior, purpose: Purpose) {
        switch unauthorizedBehavior {
        case .presentError(from: let viewController):
            Self.presentContactAccessDeniedAlert(from: viewController, purpose: purpose)
        }
    }

    func checkEditingAuthorization(authorizedBehavior: AuthorizedBehavior, unauthorizedBehavior: UnauthorizedBehavior) {
        AssertIsOnMainThread()

        switch contactsManagerImpl.editingAuthorization {
        case .denied, .restricted:
            perform(unauthorizedBehavior: unauthorizedBehavior, purpose: .edit)
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
            self.perform(unauthorizedBehavior: unauthorizedBehavior, purpose: internalPurpose)
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

        case .share, .invite:
            // TODO: Use separate copy for .share.
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
}
