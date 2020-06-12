//
// Created by Dean Eigenmann on 14.04.20.
// Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import Contacts
import ContactsUI
import SignalServiceKit
import SignalMessaging

@objc
public class OWSAddToContactViewController: OWSViewController {

    private var contactsViewHelper: ContactsViewHelper!
    private let address: SignalServiceAddress
    private var tableView: UITableView!

    private lazy var contacts = [Contact]()

    fileprivate let contactCellReuseIdentifier = "contactCellReuseIdentifier"

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    @objc public init(address: SignalServiceAddress) {
        self.address = address
        super.init(nibName: nil, bundle: nil)
        self.contactsViewHelper = ContactsViewHelper(delegate: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()

        self.view = UIView()
        let tableView = UITableView()
        self.tableView = tableView

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
            return;
        }

        let cnContact = contactsManager.cnContact(withId: contact.cnContactId)
        guard let contactViewController = contactsViewHelper.contactViewController(for: address, editImmediately: true, addToExisting: cnContact) else {
            return;
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

        let dataSource = contacts
        let contact = dataSource[indexPath.row]

        cell.configure(contact: contact, subtitleType: .none, showsWhenSelected: false, contactsManager: self.contactsManager)

        return cell
    }

}

extension OWSAddToContactViewController: ContactsViewHelperDelegate {
    public func contactsViewHelperDidUpdateContacts() {
        updateData()
        tableView.reloadData()
    }
}

extension OWSAddToContactViewController: CNContactViewControllerDelegate {

    public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        guard let index = navigationController?.viewControllers.index(of: self) else { return }

        let previous = (navigationController?.viewControllers[index - 1])!;
        navigationController?.popToViewController(previous, animated: true)

        _ = navigationController?.popViewController(animated: true)
    }

}
