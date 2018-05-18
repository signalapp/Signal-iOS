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
            owsFail("\(logTag) in \(#function) mergedContact was unexpectedly nil")
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

        let modal = OWSNavigationController(rootViewController: contactViewController)

        // HACK otherwise CNContactViewController Navbar is shows window background color.
        // RADAR rdar://28433898 http://www.openradar.me/28433898
        // CNContactViewController incompatible with opaque navigation bar
        modal.navigationBar.isTranslucent = true
        if #available(iOS 10, *) {
            // Contact navbar is blue in iOS9, so our white text works,
            // but gray on iOS10+, in which case we want the system default black text.
            UIUtil.applyDefaultSystemAppearence()
        }

        self.present(modal, animated: true)
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
            owsFail("\(logTag) in \(#function) myIndex was unexpectedly nil")
            navigationController.popViewController(animated: true)
            navigationController.popViewController(animated: true)
            return
        }

        // HACK otherwise CNContactViewController Navbar is shows window background color.
        // RADAR rdar://28433898 http://www.openradar.me/28433898
        // CNContactViewController incompatible with opaque navigation bar
        navigationController.navigationBar.isTranslucent = false
        if #available(iOS 10, *) {
            // Contact navbar is blue in iOS9, so our white text works,
            // but gray on iOS10+, in which case we want the system default black text.
            UIUtil.applySignalAppearence()
        }

        let previousViewControllerIndex = navigationController.viewControllers.index(before: myIndex)
        let previousViewController = navigationController.viewControllers[previousViewControllerIndex]

        self.dismiss(animated: false) {
            navigationController.popToViewController(previousViewController, animated: true)
        }
    }
}
