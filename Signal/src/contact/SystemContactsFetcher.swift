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
    var contactsChangedNotificationName: Notification.Name { get }
    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void)
    func fetchContacts() -> Result<[Contact], Error>
}

@available(iOS 9.0, *)
class ContactsFrameworkContactStoreAdaptee: ContactStoreAdaptee {
    let TAG = "[ContactsFrameworkContactStoreAdaptee]"
    private let contactStore = CNContactStore()

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

    var contactsChangedNotificationName: Notification.Name {
        return .CNContactStoreDidChange
    }

    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void) {
        self.contactStore.requestAccess(for: .contacts, completionHandler: completionHandler)
    }

    func fetchContacts() -> Result<[Contact], Error> {
        var systemContacts = [CNContact]()
        do {
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: self.allowedContactKeys)
            try self.contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                systemContacts.append(contact)
            }
        } catch let error as NSError {
            Logger.error("\(self.TAG) Failed to fetch contacts with error:\(error)")
            assertionFailure()
            return .error(error)
        }

        let contacts = systemContacts.map { Contact(systemContact: $0) }
        return .success(contacts)
    }
}

class AddressBookContactStoreAdaptee: ContactStoreAdaptee {
    var authorizationStatus: ContactStoreAuthorizationStatus {
        //TODO
        return .denied
    }

    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void) {
        // TODO
    }

    func fetchContacts() -> Result<[Contact], Error> {
        // TODO
        return .success([])
    }

    var contactsChangedNotificationName: Notification.Name {
        return Notification.Name("TODO")
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

    var authorizationStatus: ContactStoreAuthorizationStatus {
        return self.adaptee.authorizationStatus
    }

    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void) {
        return self.adaptee.requestAccess(completionHandler: completionHandler)
    }

    func fetchContacts() -> Result<[Contact], Error> {
        return self.adaptee.fetchContacts()
    }

    var contactsChangedNotificationName: Notification.Name {
        return self.adaptee.contactsChangedNotificationName
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
            assertionFailure("should have called `requestOnce` before this point.")
            Logger.error("\(TAG) should have called `requestOnce` before checking authorization status.")
            return false
        }

        return self.authorizationStatus == .authorized
    }

    private var systemContactsHaveBeenRequestedAtLeastOnce = false

    override init() {
        self.contactStoreAdapter = ContactStoreAdapter()
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
            Logger.debug("\(TAG) already requested system contacts")
            completion?(nil)
            return
        }
        systemContactsHaveBeenRequestedAtLeastOnce = true
        self.startObservingContactChanges()

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
                    Logger.info("\(self.TAG) declined contact access.")
                    // This case should have been caught be the error guard a few lines up.
                    assertionFailure()
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

    public func fetchIfAlreadyAuthorized() {
        AssertIsOnMainThread()
        guard authorizationStatus == .authorized else {
            return
        }

        updateContacts(completion: nil)
    }

    private func updateContacts(completion: ((Error?) -> Void)?) {
        AssertIsOnMainThread()

        systemContactsHaveBeenRequestedAtLeastOnce = true

        DispatchQueue.global().async {

            var fetchedContacts: [Contact]?

            switch self.contactStoreAdapter.fetchContacts() {
            case .success(let result):
                fetchedContacts = result
            case .error(let error):
                completion?(error)
                return
            }

            guard let contacts = fetchedContacts else {
                Logger.error("\(self.TAG) contacts was unexpectedly not set.")
                assertionFailure()
                completion?(nil)
            }

            let contactsHash  = HashableArray(contacts).hashValue

            DispatchQueue.main.async {
                var shouldNotifyDelegate = false

                if self.lastContactUpdateHash != contactsHash {
                    Logger.info("\(self.TAG) contact hash changed. new contactsHash: \(contactsHash)")
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

                Logger.debug("\(self.TAG) Notifying delegate that system contacts did change. hash:\(contactsHash)")

                self.lastDelegateNotificationDate = Date()
                self.lastContactUpdateHash = contactsHash

                self.delegate?.systemContactsFetcher(self, updatedContacts: contacts)
                completion?(nil)
            }
        }
    }

    private func startObservingContactChanges() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(contactStoreDidChange),
            name: self.contactStoreAdapter.contactsChangedNotificationName,
            object: nil)
    }

    @objc
    private func contactStoreDidChange() {
        updateContacts(completion: nil)
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
        return elements.reduce(base) { (result, element) -> Int in
            return result ^ element.hashValue
        }
    }

    static func == (lhs: HashableArray, rhs: HashableArray) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}
