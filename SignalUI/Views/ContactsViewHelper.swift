//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import ContactsUI
import LibSignalClient
import SafariServices
import SignalMessaging
import SignalServiceKit

@objc
public protocol ContactsViewHelperObserver: AnyObject {
    func contactsViewHelperDidUpdateContacts()
}

public class ContactsViewHelper: Dependencies {

    public init() {
        AppReadiness.runNowOrWhenUIDidBecomeReadySync {
            self.setup()
        }
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setup() {
        guard !CurrentAppContext().isNSE else { return }

        setupNotificationObservations()
    }

    // MARK: Notifications

    private var notificationObservers = [NSObjectProtocol]()

    private func setupNotificationObservations() {
        notificationObservers.append(contentsOf: [
            NotificationCenter.default.addObserver(
                forName: .OWSContactsManagerSignalAccountsDidChange,
                object: nil,
                queue: nil,
                using: { [weak self] _ in
                    self?.updateContacts()
                }
            ),
            NotificationCenter.default.addObserver(
                forName: UserProfileNotifications.profileWhitelistDidChange,
                object: nil,
                queue: nil,
                using: { [weak self] _ in
                    self?.updateContacts()
                }
            ),
            NotificationCenter.default.addObserver(
                forName: BlockingManager.blockListDidChange,
                object: nil,
                queue: nil,
                using: { [weak self] _ in
                    self?.updateContacts()
                }
            ),
            NotificationCenter.default.addObserver(
                forName: RecipientHidingManagerImpl.hideListDidChange,
                object: nil,
                queue: nil,
                using: { [weak self] _ in
                    // Hiding a recipient who is a system contact or is someone you've
                    // chatted with 1:1 updates the profile whitelist, which already
                    // triggers a call to `updateContacts`. However, recipients who
                    // do not fit into these categories need this other mechanism to
                    // trigger `updateContacts`.
                    self?.updateContacts()
                }
            )
        ])
    }

    // MARK: Observation

    private let observers = NSHashTable<ContactsViewHelperObserver>.weakObjects()

    public func addObserver(_ observer: ContactsViewHelperObserver) {
        AssertIsOnMainThread()
        observers.add(observer)
    }

    private func updateContacts() {
        AssertIsOnMainThread()
        owsAssertDebug(!CurrentAppContext().isNSE)
        fireDidUpdateContacts()
    }

    private func fireDidUpdateContacts() {
        for delegate in observers.allObjects {
            delegate.contactsViewHelperDidUpdateContacts()
        }
    }
}

// MARK: Presenting Permission-Gated Views

public extension ContactsViewHelper {

    private enum Constant {
        static let contactsAccessNotAllowedLearnMoreURL = URL(string: "https://support.signal.org/hc/articles/360007319011#ipad_contacts")!
    }

    enum ReadPurpose {
        case share
        case invite
    }

    private enum Access {
        case edit
        case read(ReadPurpose)
    }

    func checkEditAuthorization(
        performWhenAllowed: () -> Void,
        presentErrorFrom viewController: UIViewController
    ) {
        AssertIsOnMainThread()

        switch contactsManagerImpl.editingAuthorization {
        case .notAllowed:
            Self.presentContactAccessNotAllowedAlert(from: viewController)
        case .denied, .restricted:
            Self.presentContactAccessDeniedAlert(from: viewController, access: .edit)
        case .authorized:
            performWhenAllowed()
        }
    }

    func checkReadAuthorization(
        purpose: ReadPurpose,
        performWhenAllowed: @escaping () -> Void,
        presentErrorFrom viewController: UIViewController
    ) {
        let deniedBlock = {
            Self.presentContactAccessDeniedAlert(from: viewController, access: .read(purpose))
        }

        switch contactsManagerImpl.sharingAuthorization {
        case .notDetermined:
            CNContactStore().requestAccess(for: .contacts) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        performWhenAllowed()
                    } else {
                        deniedBlock()
                    }
                }
            }
        case .authorized:
            performWhenAllowed()
        case .denied:
            deniedBlock()
        }
    }

    private static func presentContactAccessDeniedAlert(from viewController: UIViewController, access: Access) {
        owsAssertDebug(!CurrentAppContext().isNSE)

        let title: String
        let message: String

        switch access {
        case .edit:
            title = OWSLocalizedString(
                "EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_TITLE",
                comment: "Alert title for when the user has just tried to edit a contacts after declining to give Signal contacts permissions"
            )
            message = OWSLocalizedString(
                "EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_BODY",
                comment: "Alert body for when the user has just tried to edit a contacts after declining to give Signal contacts permissions"
            )

        case .read(let readPurpose):
            switch readPurpose {
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
