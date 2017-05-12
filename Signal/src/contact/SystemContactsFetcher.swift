//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import Contacts
import ContactsUI

@objc protocol SystemContactsFetcherDelegate: class {
    func systemContactsFetcher(_ systemContactsFetcher: SystemContactsFetcher, updatedContacts contacts: [Contact])
}

@objc
class SystemContactsFetcher: NSObject {

    private let TAG = "[SystemContactsFetcher]"
    var lastContactUpdateHash: Int?
    var lastDelegateNotificationDate: Date?

    public weak var delegate: SystemContactsFetcherDelegate?

    public var authorizationStatus: CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: CNEntityType.contacts)
    }

    public var isAuthorized: Bool {
        guard self.authorizationStatus != .notDetermined else {
            assertionFailure("should have called `requestOnce` before this point.")
            Logger.error("\(TAG) should have called `requestOnce` before checking authorization status.")
            return false
        }

        return self.authorizationStatus == .authorized
    }

    private let contactStore = CNContactStore()
    private var systemContactsHaveBeenRequestedAtLeastOnce = false
    private let allowedContactKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactThumbnailImageDataKey as CNKeyDescriptor, // TODO full image instead of thumbnail?
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactViewController.descriptorForRequiredKeys()
    ]

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
            contactStore.requestAccess(for: .contacts) { (granted, error) in
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

        DispatchQueue.default.async {
            var systemContacts = [CNContact]()
            do {
                let contactFetchRequest = CNContactFetchRequest(keysToFetch: self.allowedContactKeys)
                try self.contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                    systemContacts.append(contact)
                }
            } catch let error as NSError {
                Logger.error("\(self.TAG) Failed to fetch contacts with error:\(error)")
                assertionFailure()
                DispatchQueue.main.async {
                    completion?(error)
                }
                return
            }

            let contacts = systemContacts.map { Contact(systemContact: $0) }
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
            name: .CNContactStoreDidChange,
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
