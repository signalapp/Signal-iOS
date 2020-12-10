//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import Contacts
import ContactsUI
import SignalServiceKit
import SignalMessaging

@objc
public class OWSAddToContactViewController: OWSViewController {

    private let address: SignalServiceAddress
    private var tableView: UITableView!

    private lazy var contacts = [Contact]()

    fileprivate let contactCellReuseIdentifier = "contactCellReuseIdentifier"

    @objc public init(address: SignalServiceAddress) {
        self.address = address
        super.init()
        contactsViewHelper.addObserver(self)
    }

    public override func loadView() {
        view = UIView()

        tableView = UITableView()

        view.addSubview(tableView)
        tableView.autoPinEdge(toSuperviewEdge: .top)
        tableView.autoPinEdge(toSuperviewEdge: .bottom)
        tableView.autoPinEdge(toSuperviewSafeArea: .leading)
        tableView.autoPinEdge(toSuperviewSafeArea: .trailing)
        tableView.delegate = self
        tableView.dataSource = self
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Auto size cells for dynamic type
        tableView.estimatedRowHeight = 60.0
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60

        tableView.allowsMultipleSelection = false

        tableView.separatorInset = UIEdgeInsets(top: 0, left: ContactCell.kSeparatorHInset, bottom: 0, right: 16)
        tableView.register(ContactCell.self, forCellReuseIdentifier: contactCellReuseIdentifier)

        title = NSLocalizedString(
            "CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
            comment: "Label for 'new contact' button in conversation settings view."
        )

        updateData()
        tableView.reloadData()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        view.backgroundColor = Theme.backgroundColor
        tableView.backgroundColor = Theme.backgroundColor
        tableView.separatorColor = Theme.cellSeparatorColor
    }

    fileprivate func presentContactViewController(forContact contact: Contact) {
        if !contactsManager.supportsContactEditing {
            return
        }

        let cnContact = contactsManager.cnContact(withId: contact.cnContactId)
        guard let contactViewController = contactsViewHelper.contactViewController(for: address, editImmediately: true, addToExisting: cnContact, updatedNameComponents: nil) else {
            return
        }

        contactViewController.delegate = self
        navigationController?.pushViewController(contactViewController, animated: true)
    }

    private func updateData() {
        contacts = contactsManager.allContacts
    }
}

extension OWSAddToContactViewController: UITableViewDelegate {

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        presentContactViewController(forContact: contactsManager.allContacts[indexPath.row])
    }
}

extension OWSAddToContactViewController: UITableViewDataSource {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        contacts.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: contactCellReuseIdentifier, for: indexPath) as? ContactCell else {
            owsFailDebug("cell had unexpected type")
            return UITableViewCell()
        }

        guard let contact = contacts[safe: indexPath.row] else {
            owsFailDebug("failed to lookup contact")
            return cell
        }

        cell.configure(contact: contact, subtitleType: .none, showsWhenSelected: false)

        return cell
    }

}

extension OWSAddToContactViewController: ContactsViewHelperObserver {
    public func contactsViewHelperDidUpdateContacts() {
        updateData()
        tableView.reloadData()
    }
}

extension OWSAddToContactViewController: CNContactViewControllerDelegate {

    public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        guard let index = navigationController?.viewControllers.firstIndex(of: self), index > 0,
            let previousVC = (navigationController?.viewControllers[index - 1]) else { return }

        navigationController?.popToViewController(previousVC, animated: true)
    }

}
