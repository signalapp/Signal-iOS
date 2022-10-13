//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

//  Originally based on EPContacts
//
//  Created by Prabaharan Elangovan on 12/10/15.
//  Parts Copyright © 2015 Prabaharan Elangovan. All rights reserved

import UIKit
import Contacts
import SignalServiceKit

@objc
public protocol ContactsPickerDelegate: AnyObject {
    func contactsPicker(_: ContactsPicker, contactFetchDidFail error: NSError)
    func contactsPickerDidCancel(_: ContactsPicker)
    func contactsPicker(_: ContactsPicker, didSelectContact contact: Contact)
    func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact])
    func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool
}

@objc
public enum SubtitleCellValue: Int {
    case phoneNumber, email, none
}

@objc
open class ContactsPicker: OWSViewController, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate {

    var tableView: UITableView!
    var searchBar: UISearchBar!

    // MARK: - Properties

    private let contactCellReuseIdentifier = "contactCellReuseIdentifier"

    private let collation = UILocalizedIndexedCollation.current()
    public var collationForTests: UILocalizedIndexedCollation { collation }
    private let contactStore = CNContactStore()

    // Data Source State
    private lazy var sections = [[CNContact]]()
    private lazy var filteredSections = [[CNContact]]()
    private lazy var selectedContacts = [Contact]()

    // Configuration
    @objc
    public weak var contactsPickerDelegate: ContactsPickerDelegate?
    private let subtitleCellType: SubtitleCellValue
    private let allowsMultipleSelection: Bool
    private let allowedContactKeys: [CNKeyDescriptor] = ContactsFrameworkContactStoreAdaptee.allowedContactKeys

    // MARK: - Initializers

    @objc
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
    public func didChangePreferredContentSize() {
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
        tableView.register(ContactCell.self, forCellReuseIdentifier: contactCellReuseIdentifier)
    }

    // MARK: - Contact Operations

    private func reloadContacts() {
        getContacts( onError: { error in
            Logger.error("failed to reload contacts with error:\(error)")
        })
    }

    private func getContacts(onError errorHandler: @escaping (_ error: Error) -> Void) {
        switch CNContactStore.authorizationStatus(for: CNEntityType.contacts) {
        case CNAuthorizationStatus.denied, CNAuthorizationStatus.restricted:
            let title = NSLocalizedString("INVITE_FLOW_REQUIRES_CONTACT_ACCESS_TITLE", comment: "Alert title when contacts disabled while trying to invite contacts to signal")
            let body = NSLocalizedString("INVITE_FLOW_REQUIRES_CONTACT_ACCESS_BODY", comment: "Alert body when contacts disabled while trying to invite contacts to signal")

            let alert = ActionSheetController(title: title, message: body)

            let dismissText = CommonStrings.cancelButton

            let cancelAction = ActionSheetAction(title: dismissText, style: .cancel, handler: {  _ in
                let error = NSError(domain: "contactsPickerErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Contacts Access"])
                self.contactsPickerDelegate?.contactsPicker(self, contactFetchDidFail: error)
                errorHandler(error)
            })
            alert.addAction(cancelAction)

            let settingsText = CommonStrings.openSettingsButton
            let openSettingsAction = ActionSheetAction(title: settingsText, style: .default, handler: { (_) in
                CurrentAppContext().openSystemSettings()
            })
            alert.addAction(openSettingsAction)

            self.presentActionSheet(alert)

        case CNAuthorizationStatus.notDetermined:
            // This case means the user is prompted for the first time for allowing contacts
            contactStore.requestAccess(for: CNEntityType.contacts) { (granted, error) -> Void in
                // At this point an alert is provided to the user to provide access to contacts. This will get invoked if a user responds to the alert
                if granted {
                    self.getContacts(onError: errorHandler)
                } else {
                    errorHandler(error!)
                }
            }

        case  CNAuthorizationStatus.authorized:
            // Authorization granted by user for this app.
            var contacts = [CNContact]()

            do {
                let contactFetchRequest = CNContactFetchRequest(keysToFetch: allowedContactKeys)
                contactFetchRequest.sortOrder = .userDefault
                try contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                    contacts.append(contact)
                }
                self.sections = collatedContacts(contacts)
            } catch {
                Logger.error("Failed to fetch contacts with error: \(error)")
            }
        @unknown default:
            errorHandler(OWSAssertionError("Unexpected enum value"))
        }
    }

    public func collatedContacts(_ contacts: [CNContact]) -> [[CNContact]] {
        let selector: Selector = #selector(getter: CNContact.nameForCollating)

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
        guard let cell = tableView.dequeueReusableCell(withIdentifier: contactCellReuseIdentifier, for: indexPath) as? ContactCell else {
            owsFailDebug("cell had unexpected type")
            return UITableViewCell()
        }

        let dataSource = filteredSections
        let cnContact = dataSource[indexPath.section][indexPath.row]
        let contact = Contact(systemContact: cnContact)

        cell.configure(contact: contact, subtitleType: subtitleCellType, showsWhenSelected: self.allowsMultipleSelection)
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
    func onTouchCancelButton() {
        contactsPickerDelegate?.contactsPickerDidCancel(self)
    }

    @objc
    func onTouchDoneButton() {
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

let ContactSortOrder = computeSortOrder()

func computeSortOrder() -> CNContactSortOrder {
    let comparator = CNContact.comparator(forNameSortOrder: .userDefault)

    let contact0 = CNMutableContact()
    contact0.givenName = "A"
    contact0.familyName = "Z"

    let contact1 = CNMutableContact()
    contact1.givenName = "Z"
    contact1.familyName = "A"

    let result = comparator(contact0, contact1)

    if result == .orderedAscending {
        return .givenName
    } else {
        return .familyName
    }
}

fileprivate extension CNContact {
    /**
     * Sorting Key used by collation
     */
    @objc
    var nameForCollating: String {
        if self.familyName.isEmpty && self.givenName.isEmpty {
            return self.emailAddresses.first?.value as String? ?? ""
        }

        let compositeName: String
        if ContactSortOrder == .familyName {
            compositeName = "\(self.familyName) \(self.givenName)"
        } else {
            compositeName = "\(self.givenName) \(self.familyName)"
        }
        return compositeName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
