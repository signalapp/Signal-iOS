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
            // setup() - especially updateContacts() - can
            // be expensive, so we don't want to run that
            // directly in runNowOrWhenAppDidBecomeReadySync().
            // That could cause 0x8badf00d crashes.
            //
            // On the other hand, the user might quickly
            // open a view (like the compose view) that uses
            // this helper. If the helper hasn't completed
            // setup, that view won't be able to display a
            // list of users to pick from. Therefore, we
            // can't use runNowOrWhenAppDidBecomeReadyAsync()
            // which might not run for many seconds after
            // the app becomes ready.
            //
            // Therefore we dispatch async to the main queue.
            // We'll run very soon after app UI becomes ready,
            // without introducing the risk of a 0x8badf00d
            // crash.
            DispatchQueue.main.async {
                self.setup()
            }
        }
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setup() {
        guard !CurrentAppContext().isNSE else { return }

        updateContacts()
        setupNotificationObservations()
    }

    // MARK: Notifications

    private var notificationObservers = [Any]()

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
                forName: .profileWhitelistDidChange,
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

    // MARK: Contacts Data

    public private(set) var allSignalAccounts: [SignalAccount] = []
    private var phoneNumberSignalAccountMap: [String: SignalAccount] = [:]
    private var serviceIdSignalAccountMap: [ServiceId: SignalAccount] = [:]

    public var hasUpdatedContactsAtLeastOnce: Bool {
        contactsManagerImpl.hasLoadedSystemContacts
    }

    public func localAddress() -> SignalServiceAddress? {
        owsAssertBeta(!CurrentAppContext().isNSE)
        return DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress
    }

    public func fetchSignalAccount(for address: SignalServiceAddress) -> SignalAccount? {
        AssertIsOnMainThread()
        owsAssertBeta(!CurrentAppContext().isNSE)

        if let serviceId = address.serviceId, let signalAccount = serviceIdSignalAccountMap[serviceId] {
            return signalAccount
        }

        if let phoneNumber = address.phoneNumber, let signalAccount = phoneNumberSignalAccountMap[phoneNumber] {
            return signalAccount
        }

        return nil
    }

    public func signalAccounts(matching searchText: String, transaction tx: SDSAnyReadTransaction) -> [SignalAccount] {
        owsAssertBeta(!CurrentAppContext().isNSE)

        // Check for matches against "Note to Self".
        var signalAccountsToSearch = allSignalAccounts
        if let localAddress = localAddress() {
            signalAccountsToSearch.append(SignalAccount(address: localAddress))
        }
        return fullTextSearcher.filterSignalAccounts(
            signalAccountsToSearch,
            searchText: searchText,
            transaction: tx
        )
    }

    public func signalAccounts(includingLocalUser: Bool) -> [SignalAccount] {
        switch includingLocalUser {
        case true:
            return allSignalAccounts

        case false:
            let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
            return allSignalAccounts
                .filter { !($0.recipientAddress.isLocalAddress || $0.contact?.hasPhoneNumber(localNumber) == true) }
        }
    }

    private func updateContacts() {
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
        var serviceIdMap = [ServiceId: SignalAccount]()

        for signalAccount in signalAccounts {
            if let phoneNumber = signalAccount.recipientPhoneNumber {
                phoneNumberMap[phoneNumber] = signalAccount
            }
            if let serviceId = signalAccount.recipientServiceId {
                serviceIdMap[serviceId] = signalAccount
            }
        }

        phoneNumberSignalAccountMap = phoneNumberMap
        serviceIdSignalAccountMap = serviceIdMap
        allSignalAccounts = contactsManagerImpl.sortSignalAccountsWithSneakyTransaction(signalAccounts)

        fireDidUpdateContacts()
    }

    private func fireDidUpdateContacts() {
        for delegate in observers.allObjects {
            delegate.contactsViewHelperDidUpdateContacts()
        }
    }
}

// MARK: UI

extension ContactsViewHelper {

    public func contactViewController(
        for address: SignalServiceAddress,
        editImmediately: Bool,
        addToExisting existingContact: CNContact? = nil,
        updatedNameComponents: PersonNameComponents? = nil
    ) -> CNContactViewController {

        AssertIsOnMainThread()
        owsAssertDebug(!CurrentAppContext().isNSE)
        owsAssertDebug(contactsManagerImpl.editingAuthorization == .authorized)

        let signalAccount = fetchSignalAccount(for: address)
        var shouldEditImmediately = editImmediately

        var contactViewController: CNContactViewController?
        var cnContact: CNContact?

        if let existingContact {
            cnContact = existingContact

            // Only add recipientId as a phone number for the existing contact if its not already present.
            if let phoneNumber = address.phoneNumber {
                let phoneNumberExists = existingContact.phoneNumbers.contains {
                    phoneNumber == $0.value.stringValue
                }

                owsAssertBeta(!phoneNumberExists, "We currently only should the 'add to existing contact' UI for phone numbers that don't correspond to an existing user.")

                if !phoneNumberExists {
                    var phoneNumbers = existingContact.phoneNumbers
                    phoneNumbers.append(CNLabeledValue(
                        label: CNLabelPhoneNumberMain,
                        value: CNPhoneNumber(stringValue: phoneNumber)
                    ))
                    let updatedContact = existingContact.mutableCopy() as! CNMutableContact
                    updatedContact.phoneNumbers = phoneNumbers
                    cnContact = updatedContact

                    // When adding a phone number to an existing contact, immediately enter "edit" mode.
                    shouldEditImmediately = true
                }

            }
        }

        if cnContact == nil, let cnContactId = signalAccount?.contact?.cnContactId {
            cnContact = contactsManager.cnContact(withId: cnContactId)
        }

        if let updatedContact = cnContact?.mutableCopy() as? CNMutableContact {
            if let givenName = updatedNameComponents?.givenName {
                updatedContact.givenName = givenName
            }
            if let familyName = updatedNameComponents?.familyName {
                updatedContact.familyName = familyName
            }

            if shouldEditImmediately {
                // Not actually a "new" contact, but this brings up the edit form rather than the "Read" form
                // saving our users a tap in some cases when we already know they want to edit.
                contactViewController = CNContactViewController(forNewContact: updatedContact)

                // Default title is "New Contact". We could give a more descriptive title, but anything
                // seems redundant - the context is sufficiently clear.
                contactViewController?.title = ""
            } else {
                contactViewController = CNContactViewController(for: updatedContact)
            }
        }

        if contactViewController == nil {
            let newContact = CNMutableContact()
            if let phoneNumber = address.phoneNumber {
                newContact.phoneNumbers = [ CNLabeledValue(
                    label: CNLabelPhoneNumberMain,
                    value: CNPhoneNumber(stringValue: phoneNumber)
                )]
            }

            databaseStorage.read { tx in
                if let givenName = profileManagerImpl.givenName(for: address, transaction: tx) {
                    newContact.givenName = givenName
                }
                if let familyName = profileManagerImpl.familyName(for: address, transaction: tx) {
                    newContact.familyName = familyName
                }
                if let profileAvatar = profileManagerImpl.profileAvatar(
                    for: address,
                    downloadIfMissing: true,
                    authedAccount: .implicit(),
                    transaction: tx
                ) {
                    newContact.imageData = profileAvatar.pngData()
                }
            }

            if let givenName = updatedNameComponents?.givenName {
                newContact.givenName = givenName
            }
            if let familyName = updatedNameComponents?.familyName {
                newContact.familyName = familyName
            }
            contactViewController = CNContactViewController(forNewContact: newContact)
        }

        contactViewController?.allowsActions = false
        contactViewController?.allowsEditing = true

        return contactViewController!
    }
}

// MARK: Presenting Permission-Gated Views

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
