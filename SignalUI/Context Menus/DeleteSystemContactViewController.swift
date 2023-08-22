//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging

class DeleteSystemContactViewController: OWSTableViewController2 {
    /// Dependencies needed by this view controller.
    /// Note that these dependencies can be accessed
    /// as global properties on `OWSTableViewController2`,
    /// but we are moving towards more explicit dependencies.
    private let dependencies: Dependencies
    private struct Dependencies {
        let contactsManager: ContactsManagerProtocol
        let databaseStorage: SDSDatabaseStorage
    }

    /// The address of the contact represented by this contact card.
    private let address: SignalServiceAddress

    /// The view controller that should present the toast
    /// confirming successful contact deletion. Note that
    /// this cannot be `self` because `self` dismisses upon
    /// successful deletion.
    private let viewControllerPresentingToast: UIViewController

    init(
        address: SignalServiceAddress,
        viewControllerPresentingToast: UIViewController,
        contactsManager: ContactsManagerProtocol,
        databaseStorage: SDSDatabaseStorage
    ) {
        self.address = address
        self.viewControllerPresentingToast = viewControllerPresentingToast
        self.dependencies = Dependencies(
            contactsManager: contactsManager,
            databaseStorage: databaseStorage
        )
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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

        let (image, nameComponents, phoneNumber) = dependencies.databaseStorage.read { tx in
            let image = avatarBuilder.avatarImage(
                forAddress: address,
                diameterPixels: Constants.avatarDiameter,
                localUserDisplayMode: .asUser,
                transaction: tx
            )
            let nameComponents = dependencies.contactsManager.nameComponents(
                for: address,
                transaction: tx
            )

            let phoneNumber = SignalRecipient.fetchRecipient(
                for: address,
                onlyIfRegistered: false,
                tx: tx
            )?.phoneNumber
            return (image, nameComponents, phoneNumber)
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
                    self.displayDeleteContactActionSheet()
                }
            )
        )
        contents.add(deleteContactSection)

        self.contents = contents
    }

    /// Displays the action sheet confirming that the user really
    /// wants to delete this contact from their system contacts.
    private func displayDeleteContactActionSheet() {
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
                guard let self else { return }
                // TODO: Delete contact and hide recipient. Ensure cell disappears when we return to the recipient picker list.
                self.dismiss(animated: true)
                self.displayDeletedContactToast()
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ))
        self.presentActionSheet(actionSheet)
    }

    /// Displays a toast confirming that a contact was
    /// successfully deleted.
    private func displayDeletedContactToast() {
        let displayName = dependencies.databaseStorage.read { tx in
            return self.dependencies.contactsManager.displayName(
                for: self.address,
                transaction: tx
            ).formattedForActionSheetTitle()
        }
        let toastMessage = String(
            format: OWSLocalizedString(
                "DELETE_CONTACT_CONFIRMATION_TOAST",
                comment: "Toast message confirming the system contact was deleted. Embeds {{The name of the user who was deleted.}}."
            ),
            displayName
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
