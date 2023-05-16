//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

//  Originally based on EPContacts
//
//  Created by Prabaharan Elangovan on 12/10/15.
//  Parts Copyright © 2015 Prabaharan Elangovan. All rights reserved

import Contacts
import SignalMessaging
import SignalServiceKit
import UIKit

public protocol ContactsPickerDelegate: AnyObject {
    func contactsPickerDidCancel(_: ContactsPicker)
    func contactsPicker(_: ContactsPicker, didSelectContact contact: Contact)
    func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact])
    func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool
}

public enum SubtitleCellValue: Int {
    case phoneNumber, email, none
}

open class ContactsPicker: OWSViewController, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate {

    var tableView: UITableView!
    var searchBar: UISearchBar!

    // MARK: - Properties

    private let collation = UILocalizedIndexedCollation.current()
    private let contactStore = CNContactStore()

    // Data Source State
    private lazy var sections = [[CNContact]]()
    private lazy var filteredSections = [[CNContact]]()
    private lazy var selectedContacts = [Contact]()

    // Configuration
    public weak var contactsPickerDelegate: ContactsPickerDelegate?
    private let subtitleCellType: SubtitleCellValue
    private let allowsMultipleSelection: Bool
    private let allowedContactKeys: [CNKeyDescriptor] = ContactsFrameworkContactStoreAdaptee.allowedContactKeys
    private let sortOrder: CNContactSortOrder = CNContactsUserDefaults.shared().sortOrder

    // MARK: - Initializers

    required public init(allowsMultipleSelection: Bool, subtitleCellType: SubtitleCellValue) {
        self.allowsMultipleSelection = allowsMultipleSelection
        self.subtitleCellType = subtitleCellType
        super.init()
    }

    // MARK: - Lifecycle Methods

    override public func loadView() {
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

        let searchBar = OWSSearchBar()
        self.searchBar = searchBar
        searchBar.delegate = self
        searchBar.sizeToFit()

        tableView.tableHeaderView = searchBar
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        searchBar.placeholder = CommonStrings.searchBarPlaceholder

        // Auto size cells for dynamic type
        tableView.estimatedRowHeight = 60.0
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60

        tableView.allowsMultipleSelection = allowsMultipleSelection

        tableView.separatorInset = UIEdgeInsets(top: 0, left: ContactCell.kSeparatorHInset, bottom: 0, right: 16)

        registerContactCell()
        initializeBarButtons()
        reloadContacts()
        updateSearchResults(searchText: "")

        NotificationCenter.default.addObserver(self, selector: #selector(self.didChangePreferredContentSize), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        view.backgroundColor = Theme.backgroundColor
        tableView.backgroundColor = Theme.backgroundColor
        tableView.separatorColor = Theme.cellSeparatorColor
    }

    @objc
    private func didChangePreferredContentSize() {
        self.tableView.reloadData()
    }

    private func initializeBarButtons() {
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(onTouchCancelButton))
        self.navigationItem.leftBarButtonItem = cancelButton

        if allowsMultipleSelection {
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(onTouchDoneButton))
            self.navigationItem.rightBarButtonItem = doneButton
        }
    }

    private func registerContactCell() {
        tableView.register(ContactCell.self, forCellReuseIdentifier: ContactCell.reuseIdentifier)
    }

    // MARK: - Contact Operations

    private func reloadContacts() {
        guard contactsManagerImpl.sharingAuthorization == .authorized else {
            return owsFailDebug("Not authorized.")
        }
        do {
            var contacts = [CNContact]()
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: allowedContactKeys)
            contactFetchRequest.sortOrder = .userDefault
            try contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                contacts.append(contact)
            }
            self.sections = collatedContacts(contacts)
        } catch {
            Logger.error("Failed to fetch contacts with error: \(error)")
        }
    }

    public func collatedContacts(_ contacts: [CNContact]) -> [[CNContact]] {
        let selector: Selector
        if sortOrder == .familyName {
            selector = #selector(getter: CNContact.collationNameSortedByFamilyName)
        } else {
            selector = #selector(getter: CNContact.collationNameSortedByGivenName)
        }

        var collated = Array(repeating: [CNContact](), count: collation.sectionTitles.count)
        for contact in contacts {
            let sectionNumber = collation.section(for: contact, collationStringSelector: selector)
            collated[sectionNumber].append(contact)
        }
        return collated
    }

    // MARK: - Table View DataSource

    open func numberOfSections(in tableView: UITableView) -> Int {
        return self.collation.sectionTitles.count
    }

    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let dataSource = filteredSections

        guard section < dataSource.count else {
            return 0
        }

        return dataSource[section].count
    }

    // MARK: - Table View Delegates

    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(ContactCell.self, for: indexPath)!

        let dataSource = filteredSections
        let cnContact = dataSource[indexPath.section][indexPath.row]
        let contact = Contact(systemContact: cnContact)

        cell.configure(contact: contact, sortOrder: sortOrder, subtitleType: subtitleCellType, showsWhenSelected: self.allowsMultipleSelection)
        let isSelected = selectedContacts.contains(where: { $0.uniqueId == contact.uniqueId })
        cell.isSelected = isSelected

        // Make sure we preserve selection across tableView.reloadData which happens when toggling between 
        // search controller
        if isSelected {
            self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else {
            self.tableView.deselectRow(at: indexPath, animated: false)
        }

        return cell
    }

    open func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath) as! ContactCell
        let deselectedContact = cell.contact!

        selectedContacts = selectedContacts.filter {
            return $0.uniqueId != deselectedContact.uniqueId
        }
    }

    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        Logger.verbose("")

        let cell = tableView.cellForRow(at: indexPath) as! ContactCell
        let selectedContact = cell.contact!

        guard contactsPickerDelegate == nil || contactsPickerDelegate!.contactsPicker(self, shouldSelectContact: selectedContact) else {
            self.tableView.deselectRow(at: indexPath, animated: false)
            return
        }

        selectedContacts.append(selectedContact)

        if !allowsMultipleSelection {
            // Single selection code
            self.contactsPickerDelegate?.contactsPicker(self, didSelectContact: selectedContact)
        }
    }

    open func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        return collation.section(forSectionIndexTitle: index)
    }

    open func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return collation.sectionIndexTitles
    }

    open func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let dataSource = filteredSections

        guard section < dataSource.count else {
            return nil
        }

        // Don't show empty sections
        if dataSource[section].count > 0 {
            guard section < collation.sectionTitles.count else {
                return nil
            }

            return collation.sectionTitles[section]
        } else {
            return nil
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        searchBar.resignFirstResponder()
    }

    // MARK: - Button Actions

    @objc
    private func onTouchCancelButton() {
        contactsPickerDelegate?.contactsPickerDidCancel(self)
    }

    @objc
    private func onTouchDoneButton() {
        contactsPickerDelegate?.contactsPicker(self, didSelectMultipleContacts: selectedContacts)
    }

    // MARK: - Search Actions
    open func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateSearchResults(searchText: searchText)
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    open func updateSearchResults(searchText: String) {
        let predicate: NSPredicate
        if searchText.isEmpty {
            filteredSections = sections
        } else {
            do {
                predicate = CNContact.predicateForContacts(matchingName: searchText)
                let filteredContacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: allowedContactKeys)
                    filteredSections = collatedContacts(filteredContacts)
            } catch {
                Logger.error("updating search results failed with error: \(error)")
            }
        }
        self.tableView.reloadData()
    }
}

extension CNContact {
    @objc
    fileprivate var collationNameSortedByGivenName: String { collationName(sortOrder: .givenName) }

    @objc
    fileprivate var collationNameSortedByFamilyName: String { collationName(sortOrder: .familyName) }

    func collationName(sortOrder: CNContactSortOrder) -> String {
        return (collationContactName(sortOrder: sortOrder) ?? (emailAddresses.first?.value as String?) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collationContactName(sortOrder: CNContactSortOrder) -> String? {
        let contactNames: [String] = [familyName.nilIfEmpty, givenName.nilIfEmpty].compacted()
        guard !contactNames.isEmpty else {
            return nil
        }
        return ((sortOrder == .familyName) ? contactNames : contactNames.reversed()).joined(separator: " ")
    }
}
