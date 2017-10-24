//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import Contacts
import ContactsUI

enum Result<T, ErrorType> {
    case success(T)
    case error(ErrorType)
}

protocol ContactStoreAdaptee {
    var authorizationStatus: ContactStoreAuthorizationStatus { get }
    var supportsContactEditing: Bool { get }
    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void)
    func fetchContacts() -> Result<[Contact], Error>
    func startObservingChanges(changeHandler: @escaping () -> Void)
}

@available(iOS 9.0, *)
class ContactsFrameworkContactStoreAdaptee: ContactStoreAdaptee {
    let TAG = "[ContactsFrameworkContactStoreAdaptee]"
    private let contactStore = CNContactStore()
    private var changeHandler: (() -> Void)?
    private var initializedObserver = false
    private var lastSortOrder: CNContactSortOrder?

    let supportsContactEditing = true

    private let allowedContactKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactThumbnailImageDataKey as CNKeyDescriptor, // TODO full image instead of thumbnail?
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactViewController.descriptorForRequiredKeys()
    ]

    var authorizationStatus: ContactStoreAuthorizationStatus {
        switch CNContactStore.authorizationStatus(for: CNEntityType.contacts) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
             return .authorized
        }
    }

    func startObservingChanges(changeHandler: @escaping () -> Void) {
        // should only call once
        assert(self.changeHandler == nil)
        self.changeHandler = changeHandler
        self.lastSortOrder = CNContactsUserDefaults.shared().sortOrder
        NotificationCenter.default.addObserver(self, selector: #selector(runChangeHandler), name: .CNContactStoreDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: .UIApplicationDidBecomeActive, object: nil)
    }

    @objc
    func didBecomeActive() {
        let currentSortOrder = CNContactsUserDefaults.shared().sortOrder

        guard currentSortOrder != self.lastSortOrder else {
            // sort order unchanged
            return
        }

        Logger.info("\(TAG) sort order changed: \(String(describing: self.lastSortOrder)) -> \(String(describing: currentSortOrder))")
        self.lastSortOrder = currentSortOrder
        self.runChangeHandler()
    }

    @objc
    func runChangeHandler() {
        guard let changeHandler = self.changeHandler else {
            owsFail("\(TAG) trying to run change handler before it was registered")
            return
        }
        changeHandler()
    }

    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void) {
        self.contactStore.requestAccess(for: .contacts, completionHandler: completionHandler)
    }

    func fetchContacts() -> Result<[Contact], Error> {
        var systemContacts = [CNContact]()
        do {
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: self.allowedContactKeys)
            contactFetchRequest.sortOrder = .userDefault
            try self.contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                systemContacts.append(contact)
            }
        } catch let error as NSError {
            owsFail("\(self.TAG) Failed to fetch contacts with error:\(error)")
            return .error(error)
        }

        let contacts = systemContacts.map { Contact(systemContact: $0) }
        return .success(contacts)
    }
}

let kAddressBookContactStoreDidChangeNotificationName = NSNotification.Name("AddressBookContactStoreAdapteeDidChange")
/**
 * System contact fetching compatible with iOS8
 */
class AddressBookContactStoreAdaptee: ContactStoreAdaptee {

    let TAG = "[AddressBookContactStoreAdaptee]"

    private var addressBook: ABAddressBook = ABAddressBookCreateWithOptions(nil, nil).takeRetainedValue()
    private var changeHandler: (() -> Void)?
    let supportsContactEditing = false

    var authorizationStatus: ContactStoreAuthorizationStatus {
        switch ABAddressBookGetAuthorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        }
    }

    @objc
    func runChangeHandler() {
        guard let changeHandler = self.changeHandler else {
            owsFail("\(TAG) trying to run change handler before it was registered")
            return
        }
        changeHandler()
    }

    func startObservingChanges(changeHandler: @escaping () -> Void) {
        // should only call once
        assert(self.changeHandler == nil)
        self.changeHandler = changeHandler

        NotificationCenter.default.addObserver(self, selector: #selector(runChangeHandler), name: kAddressBookContactStoreDidChangeNotificationName, object: nil)

        let callback: ABExternalChangeCallback = { (_, _, _) in
            // Ideally we'd just call the changeHandler here, but because this is a C style callback in swift, 
            // we can't capture any state in the closure, so we use a notification as a trampoline
            NotificationCenter.default.postNotificationNameAsync(kAddressBookContactStoreDidChangeNotificationName, object: nil)
        }

        ABAddressBookRegisterExternalChangeCallback(addressBook, callback, nil)
    }

    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void) {
        ABAddressBookRequestAccessWithCompletion(addressBook, completionHandler)
    }

    func fetchContacts() -> Result<[Contact], Error> {
        // Changes are not reflected unless we create a new address book
        self.addressBook = ABAddressBookCreateWithOptions(nil, nil).takeRetainedValue()

        let allPeople = ABAddressBookCopyArrayOfAllPeopleInSourceWithSortOrdering(addressBook, nil, ABPersonGetSortOrdering()).takeRetainedValue() as [ABRecord]

        let contacts = allPeople.map { self.buildContact(abRecord: $0) }

        return .success(contacts)
    }

    private func buildContact(abRecord: ABRecord) -> Contact {

        let addressBookRecord = OWSABRecord(abRecord: abRecord)

        var firstName = addressBookRecord.firstName
        let lastName = addressBookRecord.lastName
        let phoneNumbers = addressBookRecord.phoneNumbers

        if firstName == nil && lastName == nil {
            if let companyName = addressBookRecord.companyName {
                firstName = companyName
            } else {
                firstName = phoneNumbers.first
            }
        }

        return Contact(contactWithFirstName: firstName,
                       andLastName: lastName,
                       andUserTextPhoneNumbers: phoneNumbers,
                       andImage: addressBookRecord.image,
                       andContactID: addressBookRecord.recordId)
    }
}

/**
 * Wrapper around ABRecord for easy property extraction.
 * Some code lifted from: 
 * https://github.com/SocialbitGmbH/SwiftAddressBook/blob/c1993fa/Pod/Classes/SwiftAddressBookPerson.swift
 */
struct OWSABRecord {

    public struct MultivalueEntry<T> {
        public var value: T
        public var label: String?
        public let id: Int

        public init(value: T, label: String?, id: Int) {
            self.value = value
            self.label = label
            self.id = id
        }
    }

    let abRecord: ABRecord

    init(abRecord: ABRecord) {
        self.abRecord = abRecord
    }

    var firstName: String? {
        return self.extractProperty(kABPersonFirstNameProperty)
    }

    var lastName: String? {
        return self.extractProperty(kABPersonLastNameProperty)
    }

    var companyName: String? {
        return self.extractProperty(kABPersonOrganizationProperty)
    }

    var recordId: ABRecordID {
        return ABRecordGetRecordID(abRecord)
    }

    // We don't yet support labels for our iOS8 users.
    var phoneNumbers: [String] {
        if let result: [MultivalueEntry<String>] = extractMultivalueProperty(kABPersonPhoneProperty) {
            return result.map { $0.value }
        } else {
            return []
        }
    }

    var image: UIImage? {
        guard ABPersonHasImageData(abRecord) else {
            return nil
        }
        guard let data = ABPersonCopyImageData(abRecord)?.takeRetainedValue() else {
            return nil
        }
        return UIImage(data: data as Data)
    }

    private func extractProperty<T>(_ propertyName: ABPropertyID) -> T? {
        let value: AnyObject? = ABRecordCopyValue(self.abRecord, propertyName)?.takeRetainedValue()
        return value as? T
    }

    fileprivate func extractMultivalueProperty<T>(_ propertyName: ABPropertyID) -> Array<MultivalueEntry<T>>? {
        guard let multivalue: ABMultiValue = extractProperty(propertyName) else { return nil }
        var array = Array<MultivalueEntry<T>>()
        for i: Int in 0..<(ABMultiValueGetCount(multivalue)) {
            let value: T? = ABMultiValueCopyValueAtIndex(multivalue, i).takeRetainedValue() as? T
            if let v: T = value {
                let id: Int = Int(ABMultiValueGetIdentifierAtIndex(multivalue, i))
                let optionalLabel = ABMultiValueCopyLabelAtIndex(multivalue, i)?.takeRetainedValue()
                array.append(MultivalueEntry(value: v,
                                             label: optionalLabel == nil ? nil : optionalLabel! as String,
                                             id: id))
            }
        }
        return !array.isEmpty ? array : nil
    }
}

enum ContactStoreAuthorizationStatus {
    case notDetermined,
         restricted,
         denied,
         authorized
}

class ContactStoreAdapter: ContactStoreAdaptee {

    let adaptee: ContactStoreAdaptee

    init() {
        if #available(iOS 9.0, *) {
            self.adaptee = ContactsFrameworkContactStoreAdaptee()
        } else {
            self.adaptee = AddressBookContactStoreAdaptee()
        }
    }

    var supportsContactEditing: Bool {
        return self.adaptee.supportsContactEditing
    }

    var authorizationStatus: ContactStoreAuthorizationStatus {
        return self.adaptee.authorizationStatus
    }

    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void) {
        return self.adaptee.requestAccess(completionHandler: completionHandler)
    }

    func fetchContacts() -> Result<[Contact], Error> {
        return self.adaptee.fetchContacts()
    }

    func startObservingChanges(changeHandler: @escaping () -> Void) {
        self.adaptee.startObservingChanges(changeHandler: changeHandler)
    }
}

@objc protocol SystemContactsFetcherDelegate: class {
    func systemContactsFetcher(_ systemContactsFetcher: SystemContactsFetcher, updatedContacts contacts: [Contact])
}

@objc
class SystemContactsFetcher: NSObject {

    private let TAG = "[SystemContactsFetcher]"
    var lastContactUpdateHash: Int?
    var lastDelegateNotificationDate: Date?
    let contactStoreAdapter: ContactStoreAdapter

    public weak var delegate: SystemContactsFetcherDelegate?

    public var authorizationStatus: ContactStoreAuthorizationStatus {
        return contactStoreAdapter.authorizationStatus
    }

    public var isAuthorized: Bool {
        guard self.authorizationStatus != .notDetermined else {
            owsFail("should have called `requestOnce` before checking authorization status.")
            return false
        }

        return self.authorizationStatus == .authorized
    }

    private var systemContactsHaveBeenRequestedAtLeastOnce = false
    private var hasSetupObservation = false
    private var isFetchingContacts = false

    override init() {
        self.contactStoreAdapter = ContactStoreAdapter()
    }

    var supportsContactEditing: Bool {
        return self.contactStoreAdapter.supportsContactEditing
    }

    private func setupObservationIfNecessary() {
        AssertIsOnMainThread()
        guard !hasSetupObservation else {
            return
        }
        hasSetupObservation = true
        self.contactStoreAdapter.startObservingChanges { [weak self] in
            DispatchQueue.main.async {
                // If contacts have changed, don't de-bounce.
                self?.updateContacts(completion: nil, alwaysNotify: false, shouldDebounce: false)
            }
        }
    }

    /**
     * Ensures we've requested access for system contacts. This can be used in multiple places,
     * where we might need contact access, but will ensure we don't wastefully reload contacts
     * if we have already fetched contacts.
     *
     * @param   completion  completion handler is called on main thread.
     */
    public func requestOnce(completion: ((Error?) -> Void)?) {
        AssertIsOnMainThread()

        guard !systemContactsHaveBeenRequestedAtLeastOnce else {
            completion?(nil)
            return
        }
        systemContactsHaveBeenRequestedAtLeastOnce = true
        setupObservationIfNecessary()

        switch authorizationStatus {
        case .notDetermined:
            self.contactStoreAdapter.requestAccess { (granted, error) in
                if let error = error {
                    Logger.error("\(self.TAG) error fetching contacts: \(error)")
                    DispatchQueue.main.async {
                        completion?(error)
                    }
                    return
                }

                guard granted else {
                    // This case should have been caught be the error guard a few lines up.
                    owsFail("\(self.TAG) declined contact access.")
                    DispatchQueue.main.async {
                        completion?(nil)
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.updateContacts(completion: completion)
                }
            }
        case .authorized:
            self.updateContacts(completion: completion)
        case .denied, .restricted:
            Logger.debug("\(TAG) contacts were \(self.authorizationStatus)")
            DispatchQueue.main.async {
                completion?(nil)
            }
        }
    }

    public func fetchIfAlreadyAuthorized(alwaysNotify: Bool = false) {
        AssertIsOnMainThread()
        guard authorizationStatus == .authorized else {
            return
        }

        updateContacts(completion: nil, alwaysNotify:alwaysNotify)
    }

    private func tryToAcquireContactFetchLock() -> Bool {
        var didAcquireLock = false
        objc_sync_enter(self)
        if !self.isFetchingContacts {
            self.isFetchingContacts = true
            didAcquireLock = true
        }
        objc_sync_exit(self)
        return didAcquireLock
    }

    private func releaseContactFetchLock() {
        objc_sync_enter(self)
        self.isFetchingContacts = false
        objc_sync_exit(self)
    }

    private func updateContacts(completion: ((Error?) -> Void)?, alwaysNotify: Bool = false, shouldDebounce: Bool = true) {
        AssertIsOnMainThread()

        systemContactsHaveBeenRequestedAtLeastOnce = true
        setupObservationIfNecessary()

        DispatchQueue.global().async {

            if shouldDebounce {
                guard self.tryToAcquireContactFetchLock() else {
                    Logger.info("\(self.TAG) ignoring redundant system contacts fetch.")
                    return
                }
            }
            defer {
                if shouldDebounce {
                    self.releaseContactFetchLock()
                }
            }

            Logger.info("\(self.TAG) fetching contacts")

            var fetchedContacts: [Contact]?
            switch self.contactStoreAdapter.fetchContacts() {
            case .success(let result):
                fetchedContacts = result
            case .error(let error):
                completion?(error)
                return
            }

            guard let contacts = fetchedContacts else {
                owsFail("\(self.TAG) contacts was unexpectedly not set.")
                completion?(nil)
            }

            let contactsHash  = HashableArray(contacts).hashValue

            DispatchQueue.main.async {
                var shouldNotifyDelegate = false

                if self.lastContactUpdateHash != contactsHash {
                    Logger.info("\(self.TAG) contact hash changed. new contactsHash: \(contactsHash)")
                    shouldNotifyDelegate = true
                } else if alwaysNotify {
                    Logger.info("\(self.TAG) ignoring debounce.")
                    shouldNotifyDelegate = true
                } else {

                    // If nothing has changed, only notify delegate (to perform contact intersection) every N hours
                    if let lastDelegateNotificationDate = self.lastDelegateNotificationDate {
                        let kDebounceInterval = TimeInterval(12 * 60 * 60)

                        let expiresAtDate = Date(timeInterval: kDebounceInterval, since:lastDelegateNotificationDate)
                        if  Date() > expiresAtDate {
                            Logger.info("\(self.TAG) debounce interval expired at: \(expiresAtDate)")
                            shouldNotifyDelegate = true
                        } else {
                            Logger.info("\(self.TAG) ignoring since debounce interval hasn't expired")
                        }
                    } else {
                        Logger.info("\(self.TAG) first contact fetch. contactsHash: \(contactsHash)")
                        shouldNotifyDelegate = true
                    }
                }

                guard shouldNotifyDelegate else {
                    Logger.info("\(self.TAG) no reason to notify delegate.")

                    completion?(nil)

                    return
                }

                self.lastDelegateNotificationDate = Date()
                self.lastContactUpdateHash = contactsHash

                self.delegate?.systemContactsFetcher(self, updatedContacts: contacts)
                completion?(nil)
            }
        }
    }
}

struct HashableArray<Element: Hashable>: Hashable {
    var elements: [Element]
    init(_ elements: [Element]) {
        self.elements = elements
    }

    var hashValue: Int {
        // random generated 32bit number
        let base = 224712574
        var position = 0
        return elements.reduce(base) { (result, element) -> Int in
            // Make sure change in sort order invalidates hash
            position += 1
            return result ^ element.hashValue + position
        }
    }

    static func == (lhs: HashableArray, rhs: HashableArray) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}
