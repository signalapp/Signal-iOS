//
//  OWSContactsManager.swift
//  Signal
//
//  Created by Tran Son on 4/11/17.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import AddressBook

@objc class OWSContactsManager: NSObject, ContactsManagerProtocol {

    static let SignalRecipientsDidChangeNotification = "OWSContactsManagerSignalRecipientsDidChangeNotification"

    private(set) var avatarCache: NSCache<NSString, UIImage>
    private var addressBookReference: Any?
    private var futureAddressBook: TOCFuture?
    private var observableContactsController: ObservableValueController
    private var life: TOCCancelTokenSource
    private var _latestContactsById: [Int: Contact]
    private var latestContactsById: [Int: Contact] {
        set(latestContactsById) {
            _latestContactsById = latestContactsById
            var contactMap = [String: Contact]()
            for contact in latestContactsById.values {
                for phoneNumber in contact.parsedPhoneNumbers {
                    if let phoneNumberE164 = phoneNumber.toE164(), phoneNumberE164.characters.count > 0 {
                        contactMap[phoneNumberE164] = contact
                    }
                }
            }
            self.contactMap = contactMap
        }
        get {
            return _latestContactsById
        }
    }
    private var contactMap: Dictionary<String, Contact>?
    private var isContactsUpdateInFlight: Bool = false

    deinit {
        life.cancel()
    }

    override init() {
        life = TOCCancelTokenSource()
        observableContactsController = ObservableValueController(initialValue: nil)
        avatarCache = NSCache()
        _latestContactsById = [Int: Contact]()
        super.init()
    }

    func doAfterEnvironmentInitSetup() {
        if #available(iOS 9.0, *) { // WARN: Incorrectly converted
            let contactStore = CNContactStore()
            contactStore.requestAccess(for: .contacts, completionHandler: {
                (granted: Bool, error: Error?) in
                if !granted {
                    // We're still using the old addressbook API.
                    // User warned if permission not granted in that setup.
                }
            })
        }
        setupAddressBookIfNecessary()
        observableContactsController.watchLatestValue(onArbitraryThread: {
            latestContacts in
            self.setupLatestContacts(contacts: latestContacts as? NSArray)
        } , untilCancelled: life.token)
    }

    func verifyABPermission() {
        setupAddressBookIfNecessary()
    }

    // MARK: - Address Book callbacks

    private func handleAddressBookChanged() {
        pullLatestAddressBook()
        intersectContacts()
        avatarCache.removeAllObjects()
    }

    // Mark: - Setup

    private func setupAddressBookIfNecessary() {
        DispatchQueue.main.async {
            if self.isContactsUpdateInFlight {
                return
            }
            // We only need to set up our address book once;
            // after that we only need to respond to onAddressBookChanged.
            if self.addressBookReference != nil {
                return
            }
            self.isContactsUpdateInFlight = true
            let future = OWSContactsManager.asyncGetAddressBook()
            future.thenDo({
                addressBook in
                // Success.
                self.addressBookReference = addressBook
                self.isContactsUpdateInFlight = false
                let cfAddressBook = addressBook as ABAddressBook
                let onAddressBookChanged: @convention(c) (ABAddressBook?, CFDictionary?, UnsafeMutableRawPointer?) -> Void = {
                    notifyAddressBook, info, context in
                    let contactsManager = context?.load(as: OWSContactsManager.self)
                    DispatchQueue.global().async {
                        contactsManager?.handleAddressBookChanged()
                    }
                }
                ABAddressBookRegisterExternalChangeCallback(cfAddressBook, onAddressBookChanged, nil) // WARN: Incorrectly converted
                DispatchQueue.global().async {
                    self.handleAddressBookChanged()
                }
            })
            future.catchDo({
                failure in
                self.isContactsUpdateInFlight = false
            })
        }
    }

    @objc private func intersectContacts() {
        intersectContacts(withRetryDelay: 1.0)
    }

    private func intersectContacts(withRetryDelay seconds: Double) {
        let success = {
            self.fireSignalRecipientsDidChange()
        }
        let failure: (Error) -> Void = {
            error in
            if error._domain == OWSSignalServiceKitErrorDomain && error._code == OWSErrorCode.contactsUpdaterRateLimit.rawValue {
                return
            }
            // Retry with exponential backoff.
            // TODO: Abort if another contact intersection succeeds in the meantime.
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: {
                self.intersectContacts(withRetryDelay: seconds * 2.0)
            })
        }
        ContactsUpdater.shared().updateSignalContactIntersection(withABContacts: allContacts(), success: success, failure: failure)
    }

    private func fireSignalRecipientsDidChange() {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: OWSContactsManager.SignalRecipientsDidChangeNotification), object: nil)
    }

    private func pullLatestAddressBook() {
        var creationError: Unmanaged<CFError>? = nil
        let addressBookRef = ABAddressBookCreateWithOptions(nil, &creationError).takeRetainedValue()
        ABAddressBookRequestAccessWithCompletion(addressBookRef as ABAddressBook, {
            (granted, error) in
            if (!granted) {
                OWSContactsManager.blockingContactDialog()
            }
        })
        observableContactsController.updateValue(getContacts(from: addressBookRef as ABAddressBook))
    }

    private func setupLatestContacts(contacts: NSArray?) {
        if let contacts = contacts {
            latestContactsById = OWSContactsManager.keyContactsById(contacts: contacts)
        }
    }

    static func blockingContactDialog() {
        switch ABAddressBookGetAuthorizationStatus() {
        case .restricted:
            let controller = UIAlertController(title: NSLocalizedString("AB_PERMISSION_MISSING_TITLE", comment: ""), message: NSLocalizedString("ADDRESSBOOK_RESTRICTED_ALERT_BODY", comment: ""), preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: NSLocalizedString("ADDRESSBOOK_RESTRICTED_ALERT_BUTTON", comment: ""), style: .default, handler: {
                action in
                exit(0)
            }))
            UIApplication.shared.keyWindow?.rootViewController?.present(controller, animated: true, completion: nil)
            break
        case .denied:
            let controller = UIAlertController(title: NSLocalizedString("AB_PERMISSION_MISSING_TITLE", comment: ""), message:NSLocalizedString("AB_PERMISSION_MISSING_BODY", comment: ""), preferredStyle: .alert)
        
            controller.addAction(UIAlertAction(title: NSLocalizedString("AB_PERMISSION_MISSING_ACTION", comment: ""), style: .default, handler: {
                action in
                UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
            })
            )
            UIApplication.shared.keyWindow?.rootViewController?.present(controller, animated: true, completion: nil)
        case .notDetermined:
            Environment.getCurrent().contactsManager.pullLatestAddressBook()
        default:
            break;
        }
    }

    // MARK: - Observables

    func getObservableContacts() -> ObservableValue {
        return observableContactsController
    }

    // MARK: - Address Book utils

    private static func asyncGetAddressBook() -> TOCFuture {
        var creationError: Unmanaged<CFError>? = nil
        let addressBookRef = ABAddressBookCreateWithOptions(nil, &creationError).takeRetainedValue()
        if creationError != nil {
            blockingContactDialog()
            return TOCFuture(failure: creationError)
        }
        let futureAddressBookSource = TOCFutureSource()
        ABAddressBookRequestAccessWithCompletion(addressBookRef as ABAddressBook, {
            granted, requestAccessError in
            if granted && ABAddressBookGetAuthorizationStatus() == .authorized {
                DispatchQueue.main.async {
                    futureAddressBookSource.trySetResult(addressBookRef)
                }
            } else {
                blockingContactDialog()
                futureAddressBookSource.trySetFailure(requestAccessError)
            }
        })
        return futureAddressBookSource.future
    }

    func getContacts(from addressBook: ABAddressBook!) -> [Contact] {
        let allPeople = ABAddressBookCopyArrayOfAllPeople(addressBook).takeRetainedValue()
        let allPeopleMutable = CFArrayCreateMutableCopy(kCFAllocatorDefault, CFArrayGetCount(allPeople), allPeople)! as [ABRecord] // FIX: Use optional value
        let sortedPeople = allPeopleMutable.sorted(by: {
            ABPersonComparePeopleByName($0, $1, ABPersonGetSortOrdering()) != .compareGreaterThan
        })
        // This predicate returns all contacts from the addressbook having at least one phone number
        let filteredContacts = sortedPeople.filter({
            record -> Bool in
            let phoneNumbers = ABRecordCopyValue(record, kABPersonPhoneProperty).takeRetainedValue()
            var result = false
            for i in 0 ..< ABMultiValueGetCount(phoneNumbers) {
                let phoneNumber = ABMultiValueCopyValueAtIndex(phoneNumbers, i).takeRetainedValue() as! String // FIX: Use optional value
                if phoneNumber.characters.count > 0 {
                    result = true
                    break
                }
            }
            return result
        })
        return filteredContacts.map({
            item in
            return contact(for: item);
        })
    }

    // MARK: - Contact/Phone Number util

    private func contact(for record: ABRecord) -> Contact {
        let recordID = ABRecordGetRecordID(record)
        var firstName = ABRecordCopyValue(record, kABPersonFirstNameProperty)?.takeRetainedValue() as? String
        let lastName = ABRecordCopyValue(record, kABPersonLastNameProperty)?.takeRetainedValue() as? String
        let phoneNumbers = self.phoneNumbers(for: record)
        if firstName == nil && lastName == nil {
            let companyName = ABRecordCopyValue(record, kABPersonOrganizationProperty).takeRetainedValue() as? String
            if companyName != nil {
                firstName = companyName
            } else if phoneNumbers.count > 0 {
                firstName = phoneNumbers.first
            }
        }
        var img: UIImage?
        if let image = ABPersonCopyImageDataWithFormat(record, kABPersonImageFormatThumbnail)?.takeRetainedValue() as Data? {
            img = UIImage(data: image)
        }
        return Contact(contactWithFirstName: firstName, andLastName: lastName, andUserTextPhoneNumbers: phoneNumbers, andImage: img, andContactID: recordID)
    }

    func latestContact(for phoneNumber: PhoneNumber) -> Contact? {
        let allContacts = self.allContacts() as NSArray
        let contactIndex = allContacts.indexOfObject(passingTest:) {
            contact, idx, stop -> Bool in
            for number in (contact as! Contact).parsedPhoneNumbers {
                if self.phoneNumber(phoneNumber1: number, matchesNumber: phoneNumber) {
                    stop.pointee = true
                    return true
                }
            }
            return false
        }
        if contactIndex != NSNotFound {
            return allContacts[contactIndex] as? Contact
        } else {
            return nil
        }
    }

    private func phoneNumber(phoneNumber1: PhoneNumber, matchesNumber phoneNumber2: PhoneNumber) -> Bool {
        return phoneNumber1.toE164() == phoneNumber2.toE164()
    }

    private func phoneNumbers(for record: ABRecord) -> [String] {
        let numberRefs = ABRecordCopyValue(record, kABPersonPhoneProperty).takeRetainedValue()
        let phoneNumbers = ABMultiValueCopyArrayOfAllValues(numberRefs).takeRetainedValue() as? [String]
        if let numbers = phoneNumbers {
            return numbers
        } else {
            return [String]()
        }
    }

    private static func keyContactsById(contacts: NSArray) -> [Int: Contact] {
        return contacts.keyed(by: {
            (contact: Any?) -> Any? in
            return Int((contact as! Contact).recordID) // FIX: Use optional value
        }) as! [Int: Contact] // FIX: Use optional value
    }

    func allContacts() -> [Contact]! {
        var allContacts = [Contact]()
        for key in latestContactsById.keys {
            let contact = latestContactsById[key]
            allContacts.append(contact!) // FIX: Use optional value
        }
        return allContacts
    }

    // MARK: - Whisper User Management

    private func getSignalUsers(from contacts: [Contact]) -> [Contact] {
        var signalContacts = [String: Contact]()
        for contact in contacts {
            if contact.isSignal() {
                signalContacts[contact.textSecureIdentifiers().first!] = contact // FIX: Use optional value
            }
        }
        return signalContacts.values.sorted(by: {
            OWSContactsManager.contactComparator()($0, $1) == .orderedAscending
        })
    }

    static func contactComparator() -> Comparator {
        let firstNameOrdering = Int(ABPersonGetSortOrdering()) == kABPersonCompositeNameFormatFirstNameFirst ? true : false
        return Contact.comparatorSortingNames(byFirstThenLast: firstNameOrdering)
    }

    func signalContacts() -> [Contact] {
        return getSignalUsers(from: allContacts())
    }

    private func unknownContactName() -> String {
        return NSLocalizedString("UNKNOWN_CONTACT_NAME", comment: "Displayed if for some reason we can't determine a contacts phone number *or* name")
    }

    func displayName(forPhoneIdentifier identifier: String?) -> String {
        guard let identifier = identifier else {
            return unknownContactName()
        }
        let contact = self.contact(for: identifier)! // FIX: Use optional value
        let displayName = (contact.fullName.characters.count > 0) ? contact.fullName : identifier;
        return displayName
    }

    func displayName(forContact contact: Contact) -> String! {
        let displayName = (contact.fullName.characters.count > 0) ? contact.fullName : unknownContactName()
        return displayName
    }

    func formattedFullName(forContact contact: Contact, font: UIFont!) -> NSAttributedString! {
        let boldFont: UIFont = UIFont.ows_mediumFont(withSize: font.pointSize)
        let boldFontAttributes: [String: Any] = [ NSFontAttributeName: boldFont, NSForegroundColorAttributeName: UIColor.black ]
        let normalFontAttributes: [String : Any] = [ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.ows_darkGray() ]
        var firstName: NSAttributedString?
        var lastName: NSAttributedString?
        if Int(ABPersonGetSortOrdering()) == kABPersonSortByFirstName {
            if let contactFirstName = contact.firstName {
                firstName = NSAttributedString(string: contactFirstName, attributes: boldFontAttributes)
            }
            if let contactLastName = contact.lastName {
                lastName = NSAttributedString(string: contactLastName, attributes: normalFontAttributes)
            }
        } else {
            if let contactFirstName = contact.firstName {
                firstName = NSAttributedString(string: contactFirstName, attributes: normalFontAttributes)
            }
            if let contactLastName = contact.lastName {
                lastName = NSAttributedString(string: contactLastName, attributes: boldFontAttributes)
            }
        }
        var leftName: NSAttributedString?
        var rightName: NSAttributedString?
        if Int(ABPersonGetCompositeNameFormat()) == kABPersonCompositeNameFormatFirstNameFirst {
            leftName = firstName
            rightName = lastName
        } else {
            leftName = lastName
            rightName = firstName
        }
        let fullNameString = NSMutableAttributedString()
        if let leftNameAttribute = leftName {
            fullNameString.append(leftNameAttribute)
        }
        if leftName != nil && rightName != nil {
            fullNameString.append(NSAttributedString(string: " "));
        }
        if let rightNameAttribute = rightName {
            fullNameString.append(rightNameAttribute)
        }
        return fullNameString;
    }

    func formattedFullName(forRecipientId recipientId: String, font: UIFont) -> NSAttributedString {
        let normalFontAttributes: [String: Any] = [NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.ows_darkGray()]
        return NSAttributedString(string: PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: recipientId), attributes: normalFontAttributes)
    }

    func contact(for identifier: String?) -> Contact? {
        guard let identifier = identifier else {
            return nil
        }
        return contactMap?[identifier]
    }

    func getOrBuildContact(for identifier: String) -> Contact {
        if let savedContact = contact(for: identifier) {
            return savedContact
        } else {
            return Contact(contactWithFirstName: unknownContactName(), andLastName: nil, andUserTextPhoneNumbers: [identifier], andImage: nil, andContactID: 0)
        }
    }

    func image(forPhoneIdentifier identifier: String?) -> UIImage? {
        let contact = self.contact(for: identifier)
        return contact?.image
    }

    func hasAddressBook() -> Bool {
        return addressBookReference != nil
    }
}
