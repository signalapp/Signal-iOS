//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import Contacts
import ContactsUI
import SignalServiceKit
import SignalMessaging
import SignalUI

@objc
public class OWSAddToContactViewController: OWSViewController {

    private let address: SignalServiceAddress
    private var tableView: UITableView!

    private lazy var contacts = [Contact]()

    @objc
    public init(address: SignalServiceAddress) {
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
        tableView.register(ContactCell.self, forCellReuseIdentifier: ContactCell.reuseIdentifier)

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
        if !contactsManagerImpl.supportsContactEditing {
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
        contacts = databaseStorage.read { transaction in
            contactsManagerImpl.allSortedContacts(transaction: transaction)
        }
    }
}

extension OWSAddToContactViewController: UITableViewDelegate {

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        presentContactViewController(forContact: contacts[indexPath.row])
    }
}

extension OWSAddToContactViewController: UITableViewDataSource {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        contacts.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let contact = contacts[safe: indexPath.row] else {
            owsFailDebug("failed to lookup contact")
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(ContactCell.self, for: indexPath)!
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
