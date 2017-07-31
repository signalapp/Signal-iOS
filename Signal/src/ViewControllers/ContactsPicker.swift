//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

//  Originally based on EPContacts
//
//  Created by Prabaharan Elangovan on 12/10/15.
//  Parts Copyright © 2015 Prabaharan Elangovan. All rights reserved

import UIKit
import Contacts

@available(iOS 9.0, *)
public protocol ContactsPickerDelegate {
    func contactsPicker(_: ContactsPicker, didContactFetchFailed error: NSError)
    func contactsPicker(_: ContactsPicker, didCancel error: NSError)
    func contactsPicker(_: ContactsPicker, didSelectContact contact: Contact)
    func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact])
    func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool
}

@available(iOS 9.0, *)
public extension ContactsPickerDelegate {
    func contactsPicker(_: ContactsPicker, didContactFetchFailed error: NSError) { }
    func contactsPicker(_: ContactsPicker, didCancel error: NSError) { }
    func contactsPicker(_: ContactsPicker, didSelectContact contact: Contact) { }
    func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact]) { }
    func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool { return true }
}

public enum SubtitleCellValue {
    case phoneNumber
    case email
}

@available(iOS 9.0, *)
open class ContactsPicker: OWSViewController, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate {

    @IBOutlet var tableView: UITableView!
    @IBOutlet var searchBar: UISearchBar!

    // MARK: - Properties

    let TAG = "[ContactsPicker]"
    let contactCellReuseIdentifier = "contactCellReuseIdentifier"
    let contactsManager: OWSContactsManager
    let collation = UILocalizedIndexedCollation.current()
    let contactStore = CNContactStore()

    // Data Source State
    lazy var sections = [[CNContact]]()
    lazy var filteredSections = [[CNContact]]()
    lazy var selectedContacts = [Contact]()

    // Configuration
    open var contactsPickerDelegate: ContactsPickerDelegate?
    var subtitleCellValue = SubtitleCellValue.phoneNumber
    var multiSelectEnabled = false
    let allowedContactKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor
    ]

    // MARK: - Lifecycle Methods

    override open func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("INVITE_FRIENDS_PICKER_TITLE", comment: "Navbar title")

        searchBar.placeholder = NSLocalizedString("INVITE_FRIENDS_PICKER_SEARCHBAR_PLACEHOLDER", comment: "Search")
        // Prevent content form going under the navigation bar
        self.edgesForExtendedLayout = []

        // Auto size cells for dynamic type
        tableView.estimatedRowHeight = 60.0
        tableView.rowHeight = UITableViewAutomaticDimension

        tableView.allowsMultipleSelection = multiSelectEnabled

        registerContactCell()
        initializeBarButtons()
        reloadContacts()
        updateSearchResults(searchText: "")

        NotificationCenter.default.addObserver(self, selector: #selector(self.didChangePreferredContentSize), name: NSNotification.Name.UIContentSizeCategoryDidChange, object: nil)
    }

    func didChangePreferredContentSize() {
        self.tableView.reloadData()
    }

    func initializeBarButtons() {
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(onTouchCancelButton))
        self.navigationItem.leftBarButtonItem = cancelButton

        if multiSelectEnabled {
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(onTouchDoneButton))
            self.navigationItem.rightBarButtonItem = doneButton
        }
    }

    fileprivate func registerContactCell() {
        tableView.register(ContactCell.nib, forCellReuseIdentifier: contactCellReuseIdentifier)
    }

    // MARK: - Initializers

    init() {
        contactsManager = Environment.getCurrent().contactsManager
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder aDecoder: NSCoder) {
        contactsManager = Environment.getCurrent().contactsManager
        super.init(coder: aDecoder)
    }

    convenience public init(delegate: ContactsPickerDelegate?) {
        self.init(delegate: delegate, multiSelection: false)
    }

    convenience public init(delegate: ContactsPickerDelegate?, multiSelection: Bool) {
        self.init()
        multiSelectEnabled = multiSelection
        contactsPickerDelegate = delegate
    }

    convenience public init(delegate: ContactsPickerDelegate?, multiSelection: Bool, subtitleCellType: SubtitleCellValue) {
        self.init()
        multiSelectEnabled = multiSelection
        contactsPickerDelegate = delegate
        subtitleCellValue = subtitleCellType
    }

    // MARK: - Contact Operations

    open func reloadContacts() {
        getContacts( onError: { error in
            Logger.error("\(self.TAG) failed to reload contacts with error:\(error)")
        })
    }

    func getContacts(onError errorHandler: @escaping (_ error: Error) -> Void) {
        switch CNContactStore.authorizationStatus(for: CNEntityType.contacts) {
            case CNAuthorizationStatus.denied, CNAuthorizationStatus.restricted:
                let title = NSLocalizedString("INVITE_FLOW_REQUIRES_CONTACT_ACCESS_TITLE", comment: "Alert title when contacts disabled while trying to invite contacts to signal")
                let body = NSLocalizedString("INVITE_FLOW_REQUIRES_CONTACT_ACCESS_BODY", comment: "Alert body when contacts disabled while trying to invite contacts to signal")

                let alert = UIAlertController(title: title, message: body, preferredStyle: UIAlertControllerStyle.alert)

                let dismissText = NSLocalizedString("TXT_CANCEL_TITLE", comment:"")

                let cancelAction = UIAlertAction(title: dismissText, style: .cancel, handler: {  _ in
                    let error = NSError(domain: "contactsPickerErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Contacts Access"])
                    self.contactsPickerDelegate?.contactsPicker(self, didContactFetchFailed: error)
                    errorHandler(error)
                    self.dismiss(animated: true, completion: nil)
                })
                alert.addAction(cancelAction)

                let settingsText = NSLocalizedString("OPEN_SETTINGS_BUTTON", comment:"Button text which opens the settings app")
                let openSettingsAction = UIAlertAction(title: settingsText, style: .default, handler: { (_) in
                    UIApplication.shared.openSystemSettings()
                })
                alert.addAction(openSettingsAction)

                self.present(alert, animated: true, completion: nil)

            case CNAuthorizationStatus.notDetermined:
                //This case means the user is prompted for the first time for allowing contacts
                contactStore.requestAccess(for: CNEntityType.contacts) { (granted, error) -> Void in
                    //At this point an alert is provided to the user to provide access to contacts. This will get invoked if a user responds to the alert
                    if granted {
                        self.getContacts(onError: errorHandler)
                    } else {
                       errorHandler(error!)
                    }
                }

            case  CNAuthorizationStatus.authorized:
                //Authorization granted by user for this app.
                var contacts = [CNContact]()

                do {
                    let contactFetchRequest = CNContactFetchRequest(keysToFetch: allowedContactKeys)
                    try contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                        contacts.append(contact)
                    }
                    self.sections = collatedContacts(contacts)
                } catch let error as NSError {
                    Logger.error("\(self.TAG) Failed to fetch contacts with error:\(error)")
                }
        }
    }

    func collatedContacts(_ contacts: [CNContact]) -> [[CNContact]] {
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
        let cell = tableView.dequeueReusableCell(withIdentifier: contactCellReuseIdentifier, for: indexPath) as! ContactCell

        let dataSource = filteredSections
        let cnContact = dataSource[indexPath.section][indexPath.row]
        let contact = Contact(systemContact: cnContact)

        cell.updateContactsinUI(contact, subtitleType: subtitleCellValue, contactsManager: self.contactsManager)
        let isSelected = selectedContacts.contains(where: { $0.uniqueId == contact.uniqueId })
        cell.isSelected = isSelected

        // Make sure we preserve selection across tableView.reloadData which happens when toggling between 
        // search controller
        if (isSelected) {
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
        let cell = tableView.cellForRow(at: indexPath) as! ContactCell
        let selectedContact = cell.contact!

        guard (contactsPickerDelegate == nil || contactsPickerDelegate!.contactsPicker(self, shouldSelectContact: selectedContact)) else {
            self.tableView.deselectRow(at: indexPath, animated: false)
            return
        }

        selectedContacts.append(selectedContact)

        if !multiSelectEnabled {
            //Single selection code
            self.dismiss(animated: true) {
                self.contactsPickerDelegate?.contactsPicker(self, didSelectContact: selectedContact)
            }
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

        if dataSource[section].count > 0 {
            guard section < collation.sectionTitles.count else {
                return nil
            }

            return collation.sectionTitles[section]
        } else {
            return nil
        }
    }

    // MARK: - Button Actions

    func onTouchCancelButton() {
        contactsPickerDelegate?.contactsPicker(self, didCancel: NSError(domain: "contactsPickerErrorDomain", code: 2, userInfo: [ NSLocalizedDescriptionKey: "User Canceled Selection"]))
        dismiss(animated: true, completion: nil)
    }

    func onTouchDoneButton() {
        contactsPickerDelegate?.contactsPicker(self, didSelectMultipleContacts: selectedContacts)
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Search Actions
    open func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateSearchResults(searchText: searchText)
    }

    open func updateSearchResults(searchText: String) {
        let predicate: NSPredicate
        if searchText.characters.count == 0 {
            filteredSections = sections
        } else {
            do {
                predicate = CNContact.predicateForContacts(matchingName: searchText)
                let filteredContacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: allowedContactKeys)
                    filteredSections = collatedContacts(filteredContacts)
            } catch let error as NSError {
                Logger.error("\(self.TAG) updating search results failed with error: \(error)")
            }
        }
        self.tableView.reloadData()
    }
}

@available(iOS 9.0, *)
let ContactSortOrder = computeSortOrder()

@available(iOS 9.0, *)
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

@available(iOS 9.0, *)
fileprivate extension CNContact {
    /**
     * Sorting Key used by collation
     */
    @objc var nameForCollating: String {
        get {
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
}
