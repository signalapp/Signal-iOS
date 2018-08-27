//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import Contacts
import ContactsUI
import SignalServiceKit

enum Result<T, ErrorType> {
    case success(T)
    case error(ErrorType)
}

protocol ContactStoreAdaptee {
    var authorizationStatus: ContactStoreAuthorizationStatus { get }
    var supportsContactEditing: Bool { get }
    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void)
    func fetchContacts() -> Result<[Contact], Error>
    func fetchCNContact(contactId: String) -> CNContact?
    func startObservingChanges(changeHandler: @escaping () -> Void)
}

public
class ContactsFrameworkContactStoreAdaptee: NSObject, ContactStoreAdaptee {
    private let contactStore = CNContactStore()
    private var changeHandler: (() -> Void)?
    private var initializedObserver = false
    private var lastSortOrder: CNContactSortOrder?

    let supportsContactEditing = true

    public static let allowedContactKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactThumbnailImageDataKey as CNKeyDescriptor, // TODO full image instead of thumbnail?
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactViewController.descriptorForRequiredKeys(),
        CNContactVCardSerialization.descriptorForRequiredKeys()
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
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: .OWSApplicationDidBecomeActive, object: nil)
    }

    @objc
    func didBecomeActive() {
        AppReadiness.runNowOrWhenAppIsReady {
            let currentSortOrder = CNContactsUserDefaults.shared().sortOrder

            guard currentSortOrder != self.lastSortOrder else {
                // sort order unchanged
                return
            }

            Logger.info("sort order changed: \(String(describing: self.lastSortOrder)) -> \(String(describing: currentSortOrder))")
            self.lastSortOrder = currentSortOrder
            self.runChangeHandler()
        }
    }

    @objc
    func runChangeHandler() {
        guard let changeHandler = self.changeHandler else {
            owsFailDebug("trying to run change handler before it was registered")
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
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: ContactsFrameworkContactStoreAdaptee.allowedContactKeys)
            contactFetchRequest.sortOrder = .userDefault
            try self.contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                systemContacts.append(contact)
            }
        } catch let error as NSError {
            owsFailDebug("Failed to fetch contacts with error:\(error)")
            return .error(error)
        }

        let contacts = systemContacts.map { Contact(systemContact: $0) }
        return .success(contacts)
    }

    func fetchCNContact(contactId: String) -> CNContact? {
        var result: CNContact?
        do {
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: ContactsFrameworkContactStoreAdaptee.allowedContactKeys)
            contactFetchRequest.sortOrder = .userDefault
            contactFetchRequest.predicate = CNContact.predicateForContacts(withIdentifiers: [contactId])

            try self.contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                guard result == nil else {
                    owsFailDebug("More than one contact with contact id.")
                    return
                }
                result = contact
            }
        } catch let error as NSError {
            owsFailDebug("Failed to fetch contact with error:\(error)")
            return nil
        }

        return result
    }
}

@objc
public enum ContactStoreAuthorizationStatus: UInt {
    case notDetermined,
         restricted,
         denied,
         authorized
}

@objc public protocol SystemContactsFetcherDelegate: class {
    func systemContactsFetcher(_ systemContactsFetcher: SystemContactsFetcher, updatedContacts contacts: [Contact], isUserRequested: Bool)
    func systemContactsFetcher(_ systemContactsFetcher: SystemContactsFetcher, hasAuthorizationStatus authorizationStatus: ContactStoreAuthorizationStatus)
}

@objc
public class SystemContactsFetcher: NSObject {

    private let serialQueue = DispatchQueue(label: "SystemContactsFetcherQueue")

    var lastContactUpdateHash: Int?
    var lastDelegateNotificationDate: Date?
    let contactStoreAdapter: ContactsFrameworkContactStoreAdaptee

    @objc
    public weak var delegate: SystemContactsFetcherDelegate?

    public var authorizationStatus: ContactStoreAuthorizationStatus {
        return contactStoreAdapter.authorizationStatus
    }

    @objc
    public var isAuthorized: Bool {
        guard self.authorizationStatus != .notDetermined else {
            owsFailDebug("should have called `requestOnce` before checking authorization status.")
            return false
        }

        return self.authorizationStatus == .authorized
    }

    @objc
    public var isDenied: Bool {
        return self.authorizationStatus == .denied
    }

    @objc
    public private(set) var systemContactsHaveBeenRequestedAtLeastOnce = false
    private var hasSetupObservation = false

    override init() {
        self.contactStoreAdapter = ContactsFrameworkContactStoreAdaptee()

        super.init()

        SwiftSingletons.register(self)
    }

    @objc
    public var supportsContactEditing: Bool {
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
                self?.refreshAfterContactsChange()
            }
        }
    }

    /**
     * Ensures we've requested access for system contacts. This can be used in multiple places,
     * where we might need contact access, but will ensure we don't wastefully reload contacts
     * if we have already fetched contacts.
     *
     * @param   completionParam  completion handler is called on main thread.
     */
    @objc
    public func requestOnce(completion completionParam: ((Error?) -> Void)?) {
        AssertIsOnMainThread()

        // Ensure completion is invoked on main thread.
        let completion = { error in
            DispatchMainThreadSafe({
                completionParam?(error)
            })
        }

        guard !systemContactsHaveBeenRequestedAtLeastOnce else {
            completion(nil)
            return
        }
        setupObservationIfNecessary()

        switch authorizationStatus {
        case .notDetermined:
            if CurrentAppContext().isInBackground() {
                Logger.error("do not request contacts permission when app is in background")
                completion(nil)
                return
            }
            self.contactStoreAdapter.requestAccess { (granted, error) in
                if let error = error {
                    Logger.error("error fetching contacts: \(error)")
                    completion(error)
                    return
                }

                guard granted else {
                    // This case should have been caught by the error guard a few lines up.
                    owsFailDebug("declined contact access.")
                    completion(nil)
                    return
                }

                DispatchQueue.main.async {
                    self.updateContacts(completion: completion)
                }
            }
        case .authorized:
            self.updateContacts(completion: completion)
        case .denied, .restricted:
            Logger.debug("contacts were \(self.authorizationStatus)")
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: authorizationStatus)
            completion(nil)
        }
    }

    @objc
    public func fetchOnceIfAlreadyAuthorized() {
        AssertIsOnMainThread()
        guard authorizationStatus == .authorized else {
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: authorizationStatus)
            return
        }
        guard !systemContactsHaveBeenRequestedAtLeastOnce else {
            return
        }

        updateContacts(completion: nil, isUserRequested: false)
    }

    @objc
    public func userRequestedRefresh(completion: @escaping (Error?) -> Void) {
        AssertIsOnMainThread()

        guard authorizationStatus == .authorized else {
            owsFailDebug("should have already requested contact access")
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: authorizationStatus)
            completion(nil)
            return
        }

        updateContacts(completion: completion, isUserRequested: true)
    }

    @objc
    public func refreshAfterContactsChange() {
        AssertIsOnMainThread()

        guard authorizationStatus == .authorized else {
            Logger.info("ignoring contacts change; no access.")
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: authorizationStatus)
            return
        }

        updateContacts(completion: nil, isUserRequested: false)
    }

    private func updateContacts(completion completionParam: ((Error?) -> Void)?, isUserRequested: Bool = false) {
        AssertIsOnMainThread()

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)", completionBlock: { [weak self] status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }

            guard let _ = self else {
                return
            }
            Logger.error("background task time ran out before contacts fetch completed.")
        })

        // Ensure completion is invoked on main thread.
        let completion: (Error?) -> Void = { error in
            DispatchMainThreadSafe({
                completionParam?(error)

                assert(backgroundTask != nil)
                backgroundTask = nil
            })
        }

        systemContactsHaveBeenRequestedAtLeastOnce = true
        setupObservationIfNecessary()

        serialQueue.async {

            Logger.info("fetching contacts")

            var fetchedContacts: [Contact]?
            switch self.contactStoreAdapter.fetchContacts() {
            case .success(let result):
                fetchedContacts = result
            case .error(let error):
                completion(error)
                return
            }

            guard let contacts = fetchedContacts else {
                owsFailDebug("contacts was unexpectedly not set.")
                completion(nil)
            }

            Logger.info("fetched \(contacts.count) contacts.")
            let contactsHash  = HashableArray(contacts).hashValue

            DispatchQueue.main.async {
                var shouldNotifyDelegate = false

                if self.lastContactUpdateHash != contactsHash {
                    Logger.info("contact hash changed. new contactsHash: \(contactsHash)")
                    shouldNotifyDelegate = true
                } else if isUserRequested {
                    Logger.info("ignoring debounce due to user request")
                    shouldNotifyDelegate = true
                } else {

                    // If nothing has changed, only notify delegate (to perform contact intersection) every N hours
                    if let lastDelegateNotificationDate = self.lastDelegateNotificationDate {
                        let kDebounceInterval = TimeInterval(12 * 60 * 60)

                        let expiresAtDate = Date(timeInterval: kDebounceInterval, since: lastDelegateNotificationDate)
                        if  Date() > expiresAtDate {
                            Logger.info("debounce interval expired at: \(expiresAtDate)")
                            shouldNotifyDelegate = true
                        } else {
                            Logger.info("ignoring since debounce interval hasn't expired")
                        }
                    } else {
                        Logger.info("first contact fetch. contactsHash: \(contactsHash)")
                        shouldNotifyDelegate = true
                    }
                }

                guard shouldNotifyDelegate else {
                    Logger.info("no reason to notify delegate.")

                    completion(nil)

                    return
                }

                self.lastDelegateNotificationDate = Date()
                self.lastContactUpdateHash = contactsHash

                self.delegate?.systemContactsFetcher(self, updatedContacts: contacts, isUserRequested: isUserRequested)
                completion(nil)
            }
        }
    }

    @objc
    public func fetchCNContact(contactId: String) -> CNContact? {
        guard authorizationStatus == .authorized else {
            Logger.error("contact fetch failed; no access.")
            return nil
        }

        return contactStoreAdapter.fetchCNContact(contactId: contactId)
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
