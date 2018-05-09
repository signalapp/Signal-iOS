//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import ContactsUI

class AddContactShareToExistingContactViewController: ContactsPicker, ContactsPickerDelegate, CNContactViewControllerDelegate {

    // TODO actual protocol?
    weak var addToExistingContactDelegate: UIViewController?

    let contactShare: ContactShareViewModel

    required init(contactShare: ContactShareViewModel) {
        self.contactShare = contactShare
        super.init(allowsMultipleSelection: false, subtitleCellType: .none)

        self.contactsPickerDelegate = self
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc required public init(allowsMultipleSelection: Bool, subtitleCellType: SubtitleCellValue) {
        fatalError("init(allowsMultipleSelection:subtitleCellType:) has not been implemented")
    }

    // MARK: - ContactsPickerDelegate

    func contactsPicker(_: ContactsPicker, contactFetchDidFail error: NSError) {
        owsFail("\(logTag) in \(#function) with error: \(error)")

        guard let navigationController = self.navigationController else {
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }

        navigationController.popViewController(animated: true)
    }

    func contactsPickerDidCancel(_: ContactsPicker) {
        Logger.debug("\(self.logTag) in \(#function)")
        guard let navigationController = self.navigationController else {
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }

        navigationController.popViewController(animated: true)
    }

    func contactsPicker(_: ContactsPicker, didSelectContact contact: Contact) {
        Logger.debug("\(self.logTag) in \(#function)")

        guard let mergedContact: CNContact = self.contactShare.cnContact(mergedWithExistingContact: contact) else {
            // TODO maybe this should not be optional and return a blank contact so we can still save the (not-actually merged) contact
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }

        // Not actually a "new" contact, but this brings up the edit form rather than the "Read" form
        // saving our users a tap in some cases when we already know they want to edit.
        let contactViewController: CNContactViewController = CNContactViewController(forNewContact: mergedContact)

        // Default title is "New Contact". We could give a more descriptive title, but anything
        // seems redundant - the context is sufficiently clear.
        contactViewController.title = ""
        contactViewController.allowsActions = false
        contactViewController.allowsEditing = true
        contactViewController.delegate = self

        guard let navigationController = self.navigationController else {
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }
        navigationController.pushViewController(contactViewController, animated: true)
    }

    func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact]) {
        Logger.debug("\(self.logTag) in \(#function)")
        owsFail("\(logTag) only supports single contact select")

        guard let navigationController = self.navigationController else {
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }

        navigationController.popViewController(animated: true)
    }

    func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool {
        return true
    }

    // MARK: - CNContactViewControllerDelegate

    public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.debug("\(self.logTag) in \(#function)")

        guard let navigationController = self.navigationController else {
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }

        // We want to pop *this* view and the still presented CNContactViewController in a single animation.
        // Note this happens for *cancel* and for *done*. Unfortunately, I don't know of a way to detect the difference
        // between the two, since both just call this method.
        guard let myIndex = navigationController.viewControllers.index(of: self) else {
            owsFail("\(logTag) in \(#function) myIndex was unexpectedly nil")
            navigationController.popViewController(animated: true)
            navigationController.popViewController(animated: true)
            return
        }

        let previousViewControllerIndex = navigationController.viewControllers.index(before: myIndex)
        let previousViewController = navigationController.viewControllers[previousViewControllerIndex]
        navigationController.popToViewController(previousViewController, animated: true)
    }
}
