//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import LibSignalClient
import SignalMessaging

/// If we try and hide a recipient but fail because they correspond to
/// a system contact, we show this controller which provides a hook
/// to delete the system contact (which, if successful, then triggers a hide).
///
/// SHOULD ONLY BE DISPLAYED ON THE PRIMARY DEVICE
class DeleteSystemContactViewController: OWSTableViewController2 {
    /// Dependencies needed by this view controller.
    /// Note that these dependencies can be accessed
    /// as global properties on `OWSTableViewController2`,
    /// but we are moving towards more explicit dependencies.
    private let dependencies: Dependencies
    private struct Dependencies {
        let contactsManager: ContactsManagerProtocol
        let databaseStorage: SDSDatabaseStorage
        let recipientHidingManager: RecipientHidingManager
        let tsAccountManager: TSAccountManager
    }

    /// The e164 of the contact represented by this contact card.
    private let e164: E164
    private let serviceId: ServiceId?

    /// The view controller that should present the toast
    /// confirming successful contact deletion. Note that
    /// this cannot be `self` because `self` dismisses upon
    /// successful deletion.
    private let viewControllerPresentingToast: UIViewController

    init(
        e164: E164,
        serviceId: ServiceId?,
        viewControllerPresentingToast: UIViewController,
        contactsManager: ContactsManagerProtocol,
        databaseStorage: SDSDatabaseStorage,
        recipientHidingManager: RecipientHidingManager,
        tsAccountManager: TSAccountManager
    ) {
        self.e164 = e164
        self.serviceId = serviceId
        self.viewControllerPresentingToast = viewControllerPresentingToast
        self.dependencies = Dependencies(
            contactsManager: contactsManager,
            databaseStorage: databaseStorage,
            recipientHidingManager: recipientHidingManager,
            tsAccountManager: tsAccountManager
        )
        super.init()
    }

    private lazy var spinnerContainer: UIView = {
        let view = UIView()
        self.view.addSubview(view)
        view.autoPinEdgesToSuperviewEdges()
        view.backgroundColor = .black.withAlphaComponent(0.15)
        view.addSubview(spinnerView)
        spinnerView.autoCenterInSuperview()
        view.isHidden = true
        return view
    }()

    private lazy var spinnerView = UIActivityIndicatorView()

    override func viewDidLoad() {
        super.viewDidLoad()

        // This screen is for primary devices only. If a non primary
        // manages to get here bad things could happen.
        owsAssert(tsAccountManager.isPrimaryDevice)

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel)
        )
    }

    @objc
    private func didTapCancel() {
        dismiss(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        updateTableContents()
    }

    private enum Constants {
        /// Width and height for avatar image.
        static let avatarDiameter = CGFloat(112)
        /// Toast inset from bottom of view.
        static let toastInset = 8.0
    }

    /// Cell containing contact avatar.
    ///
    /// - Parameter image: The avatar image.
    private func avatarCell(image: UIImage) -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        cell.contentView.backgroundColor = .clear

        let imageView = ContactDeletionAvatarImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentCompressionResistancePriority(.required, for: .vertical)

        cell.contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: Constants.avatarDiameter),
            imageView.widthAnchor.constraint(equalToConstant: Constants.avatarDiameter),
            cell.contentView.topAnchor.constraint(equalTo: imageView.topAnchor),
            cell.contentView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            cell.contentView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor)
        ])
        return cell
    }

    /// Ordered array of names to be displayed on the contact card.
    /// Each name should have its own cell in the same section.
    /// If the contact has no associated names, this method returns
    /// an empty array.
    ///
    /// - Parameter nameComponents: The name components of the person whose names
    ///   we will return.
    private func names(nameComponents: PersonNameComponents?) -> [String] {
        guard let nameComponents = nameComponents else {
            return []
        }
        if let nickname = nameComponents.nickname {
            return [nickname]
        }
        var names = [String]()
        if let firstName = nameComponents.givenName {
            names.append(firstName)
        }
        if let lastName = nameComponents.familyName {
            names.append(lastName)
        }
        return names
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let addressForProfileLookup = SignalServiceAddress(serviceId: serviceId, e164: e164)
        let (
            image,
            nameComponents,
            displayNameForToast,
            phoneNumber
        ) = dependencies.databaseStorage.read { tx in
            let image = avatarBuilder.avatarImage(
                forAddress: addressForProfileLookup,
                diameterPixels: Constants.avatarDiameter * UIScreen.main.scale,
                localUserDisplayMode: .asUser,
                transaction: tx
            )
            let nameComponents = dependencies.contactsManager.nameComponents(
                for: addressForProfileLookup,
                transaction: tx
            )
            let displayNameForToast = dependencies.contactsManager.displayName(
                for: addressForProfileLookup,
                transaction: tx
            ).formattedForActionSheetTitle()
            let phoneNumber = SignalRecipient.fetchRecipient(
                for: addressForProfileLookup,
                onlyIfRegistered: false,
                tx: tx
            )?.phoneNumber
            return (
                image,
                nameComponents,
                displayNameForToast,
                phoneNumber
            )
        }

        // Avatar
        let avatarSection = OWSTableSection()
        avatarSection.hasBackground = false
        let avatarItem = OWSTableItem(customCellBlock: { [weak self] in
            if
                let image = image,
                let avatarCell = self?.avatarCell(image: image)
            {
                return avatarCell
            }
            return UITableViewCell()
        })
        avatarSection.add(avatarItem)
        contents.add(avatarSection)

        // Name(s)
        let names = names(nameComponents: nameComponents)
        if !names.isEmpty {
            let nameSection = OWSTableSection()
            names.forEach { name in
                nameSection.add(
                    OWSTableItem.label(
                        withText: name,
                        accessoryType: .none
                    )
                )
            }
            contents.add(nameSection)
        }

        // Phone Number
        if let signalPhoneNum = phoneNumber {
            let formattedPhoneNum = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: signalPhoneNum)
            let phoneNumberSection = OWSTableSection()
            phoneNumberSection.add(
                OWSTableItem.label(
                    withText: formattedPhoneNum,
                    accessoryType: .none
                )
            )
            contents.add(phoneNumberSection)
        }

        // Delete Contact button
        let deleteContactSection = OWSTableSection()
        deleteContactSection.add(
            OWSTableItem(
                customCellBlock: {
                    return OWSTableItem.buildCell(
                        itemName: OWSLocalizedString(
                            "DELETE_CONTACT_BUTTON",
                            comment: "Title of button for deleting system contact."
                        ),
                        textColor: .ows_accentRed,
                        accessoryType: .none
                    )
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    self.displayDeleteContactActionSheet(phoneNumber: phoneNumber, displayNameForToast: displayNameForToast)
                }
            )
        )
        contents.add(deleteContactSection)

        self.contents = contents
    }

    /// Displays the action sheet confirming that the user really
    /// wants to delete this contact from their system contacts.
    private func displayDeleteContactActionSheet(phoneNumber: String?, displayNameForToast: String) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DELETE_CONTACT_ACTION_SHEET_TITLE",
                comment: "Title of action sheet confirming the user wants to delete a system contact."
            ),
            message: OWSLocalizedString(
                "DELETE_CONTACT_ACTION_SHEET_EXPLANATION",
                comment: "An explanation of what happens in Signal when you remove a system contact."
            )
        )

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "DELETE_CONTACT_ACTION_SHEET_BUTTON",
                comment: "'Delete' button label on the delete contact confirmation action sheet"
            ),
            style: .destructive,
            handler: { [weak self] _ in
                self?.handleContactDelete(displayNameForToast: displayNameForToast)
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ))
        self.presentActionSheet(actionSheet)
    }

    private func handleContactDelete(displayNameForToast: String) {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            break
        case .notDetermined, .denied, .restricted:
            fallthrough
        @unknown default:
            Logger.info("No contact permissions")
            showGenericErrorToastAndDismiss()
        }

        let signalAccount = self.dependencies.databaseStorage.read { tx in
            return SignalAccountFinder().signalAccount(
                for: self.e164,
                tx: tx
            )
        }
        // In the case where we have more than one contact with the e164,
        // prefer the one with this id. Otherwise, choice is arbitrary.
        let preferredContactIdForDeletion = signalAccount?.contact?.cnContactId

        // Go to CNContacts as the source of truth for contacts.
        let contactStore = CNContactStore()
        let phoneNumPredicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: e164.stringValue))
        guard
            let contacts = try? contactStore.unifiedContacts(
                    matching: phoneNumPredicate,
                    keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
                )
        else {
            Logger.error("Failed to fetch CNContacts!")
            showGenericErrorToastAndDismiss()
            return
        }
        var contactToDelete: CNContact?
        if let preferredContactIdForDeletion {
            contactToDelete = contacts.first(where: { $0.identifier == preferredContactIdForDeletion })
        }
        if contactToDelete == nil {
            contactToDelete = contacts.first
        }

        guard let contactToDelete = contactToDelete?.mutableCopy() as? CNMutableContact else {
            // No contact to delete! Done.
            Logger.warn("No contact to delete, exiting early.")
            showGenericErrorToastAndDismiss()
            return
        }

        var didFail = false
        // Set up the observer _before_ deleting, so its around
        // when the deletion happens.
        NotificationCenter.default.observe(once: .OWSContactsManagerSignalAccountsDidChange)
            .asVoid()
            .timeout(on: DispatchQueue.main, seconds: 5, substituteValue: ())
            .observe(on: DispatchQueue.main) { [weak self] _ in
                guard let self, !didFail else { return }

                defer {
                    self.dismiss(animated: true)
                    self.displayDeletedContactToast(displayNameForToast: displayNameForToast)
                }

                // Check that the contact got deleted from our db.
                let isStillSystemContact = self.dependencies.databaseStorage.read { tx in
                    return self.contactsManager.isSystemContact(phoneNumber: self.e164.stringValue, transaction: tx)
                }
                guard !isStillSystemContact else {
                    // Can't hide; likely there was another contact with the same number.
                    // Just exit.
                    Logger.warn("Address still a system contact after deletion; possibly duplicate system contact")
                    return
                }
                self.dependencies.databaseStorage.write { tx in
                    do {
                        try self.dependencies.recipientHidingManager.addHiddenRecipient(
                            SignalServiceAddress(serviceId: self.serviceId, e164: self.e164),
                            wasLocallyInitiated: true,
                            tx: tx.asV2Write
                        )
                    } catch {
                        owsFailDebug("Failed to hide recipient")
                    }
                }
            }

        // Delete
        let saveRequest = CNSaveRequest()
        saveRequest.delete(contactToDelete)
        do {
            try contactStore.execute(saveRequest)
        } catch {
            didFail = true
            Logger.error("Failed to delete CNContact!")
            showGenericErrorToastAndDismiss()
        }

        spinnerContainer.isHidden = false
        spinnerView.startAnimating()
        self.view.isUserInteractionEnabled = false
    }

    private func showGenericErrorToastAndDismiss() {
        ToastController(text: CommonStrings.somethingWentWrongError).presentToastView(
            from: .bottom,
            of: self.viewControllerPresentingToast.view,
            inset: self.view.safeAreaInsets.bottom + Constants.toastInset
        )
        self.dismiss(animated: true)
    }

    /// Displays a toast confirming that a contact was
    /// successfully deleted.
    private func displayDeletedContactToast(displayNameForToast: String) {
        let toastMessage = String(
            format: OWSLocalizedString(
                "DELETE_CONTACT_CONFIRMATION_TOAST",
                comment: "Toast message confirming the system contact was deleted. Embeds {{The name of the user who was deleted.}}."
            ),
            displayNameForToast
        )
        ToastController(text: toastMessage).presentToastView(
            from: .bottom,
            of: self.viewControllerPresentingToast.view,
            inset: self.view.safeAreaInsets.bottom + Constants.toastInset
        )
    }
}

private class ContactDeletionAvatarImageView: UIImageView {
    override public func layoutSubviews() {
        super.layoutSubviews()
        self.clipsToBounds = true
        layer.cornerRadius = self.frame.size.width / 2
    }
}
