//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import ContactsUI

class AddContactShareToExistingContactViewController: ContactsPicker, ContactsPickerDelegate, CNContactViewControllerDelegate {

    // TODO - there are some hard coded assumptions in this VC that assume we are *pushed* onto a
    // navigation controller. That seems fine for now, but if we need to be presented as a modal,
    // or need to notify our presenter about our dismisall or other contact actions, a delegate
    // would be helpful. It seems like this would require some broad changes to the ContactShareViewHelper,
    // so I've left it as is for now, since it happens to work.
    // weak var addToExistingContactDelegate: AddContactShareToExistingContactViewControllerDelegate?

    let contactShare: ContactShareViewModel

    required init(contactShare: ContactShareViewModel) {
        self.contactShare = contactShare
        super.init(allowsMultipleSelection: false, subtitleCellType: .none)

        self.contactsPickerDelegate = self
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc required public init(allowsMultipleSelection: Bool, subtitleCellType: SubtitleCellValue) {
        notImplemented()
    }

    // MARK: - ContactsPickerDelegate

    func contactsPicker(_: ContactsPicker, contactFetchDidFail error: NSError) {
        owsFailDebug("with error: \(error)")

        guard let navigationController = self.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        navigationController.popViewController(animated: true)
    }

    func contactsPickerDidCancel(_: ContactsPicker) {
        Logger.debug("")
        guard let navigationController = self.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        navigationController.popViewController(animated: true)
    }

    func contactsPicker(_: ContactsPicker, didSelectContact oldContact: Contact) {
        Logger.debug("")

        let contactsManager = Environment.shared.contactsManager
        guard let oldCNContact = contactsManager?.cnContact(withId: oldContact.cnContactId) else {
            owsFailDebug("could not load old CNContact.")
            return
        }
        guard let newCNContact = OWSContacts.systemContact(for: self.contactShare.dbRecord, imageData: self.contactShare.avatarImageData) else {
            owsFailDebug("could not load new CNContact.")
            return
        }
        merge(oldCNContact: oldCNContact, newCNContact: newCNContact)
    }

    func merge(oldCNContact: CNContact, newCNContact: CNContact) {
        Logger.debug("")

        let mergedCNContact: CNContact = Contact.merge(cnContact: oldCNContact, newCNContact: newCNContact)

        // Not actually a "new" contact, but this brings up the edit form rather than the "Read" form
        // saving our users a tap in some cases when we already know they want to edit.
        let contactViewController: CNContactViewController = CNContactViewController(forNewContact: mergedCNContact)

        // Default title is "New Contact". We could give a more descriptive title, but anything
        // seems redundant - the context is sufficiently clear.
        contactViewController.title = ""
        contactViewController.allowsActions = false
        contactViewController.allowsEditing = true
        contactViewController.delegate = self

        let modal = OWSNavigationController(rootViewController: contactViewController)
        self.present(modal, animated: true)
    }

    func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact]) {
        Logger.debug("")
        owsFailDebug("only supports single contact select")

        guard let navigationController = self.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        navigationController.popViewController(animated: true)
    }

    func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool {
        return true
    }

    // MARK: - CNContactViewControllerDelegate

    public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.debug("")

        guard let navigationController = self.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        // TODO this is weird - ideally we'd do something like
        //     self.delegate?.didFinishAddingContact
        // and the delegate, which knows about our presentation context could do the right thing.
        //
        // As it is, we happen to always be *pushing* this view controller onto a navcontroller, so the
        // following works in all current cases.
        //
        // If we ever wanted to do something different, like present this in a modal, we'd have to rethink.

        // We want to pop *this* view *and* the still presented CNContactViewController in a single animation.
        // Note this happens for *cancel* and for *done*. Unfortunately, I don't know of a way to detect the difference
        // between the two, since both just call this method.
        guard let myIndex = navigationController.viewControllers.index(of: self) else {
            owsFailDebug("myIndex was unexpectedly nil")
            navigationController.popViewController(animated: true)
            navigationController.popViewController(animated: true)
            return
        }

        let previousViewControllerIndex = navigationController.viewControllers.index(before: myIndex)
        let previousViewController = navigationController.viewControllers[previousViewControllerIndex]

        self.dismiss(animated: false) {
            navigationController.popToViewController(previousViewController, animated: true)
        }
    }
}
