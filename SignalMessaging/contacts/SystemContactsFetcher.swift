//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
    var rawAuthorizationStatus: RawContactAuthorizationStatus { get }
    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void)
    func fetchContacts() -> Result<[Contact], Error>
    func fetchCNContact(contactId: String) -> CNContact?
    func startObservingChanges(changeHandler: @escaping () -> Void)
}

public
class ContactsFrameworkContactStoreAdaptee: NSObject, ContactStoreAdaptee {
    private let contactStoreForLargeRequests = CNContactStore()
    private let contactStoreForSmallRequests = CNContactStore()
    private var changeHandler: (() -> Void)?
    private var initializedObserver = false
    private var lastSortOrder: CNContactSortOrder?

    private static let minimalContactKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor
    ]

    private static let fullContactKeys: [CNKeyDescriptor] = ContactsFrameworkContactStoreAdaptee.minimalContactKeys + [
        CNContactThumbnailImageDataKey as CNKeyDescriptor, // TODO full image instead of thumbnail?
        CNContactViewController.descriptorForRequiredKeys(),
        CNContactVCardSerialization.descriptorForRequiredKeys()
    ]

    public static var allowedContactKeys: [CNKeyDescriptor] {
        if CurrentAppContext().isNSE {
            return minimalContactKeys
        } else {
            return fullContactKeys
        }
    }

    var rawAuthorizationStatus: RawContactAuthorizationStatus {
        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        switch authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
             return .authorized
        @unknown default:
            owsFailDebug("unexpected value: \(authorizationStatus.rawValue)")
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
    private func didBecomeActive() {
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
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
    private func runChangeHandler() {
        guard let changeHandler = self.changeHandler else {
            owsFailDebug("trying to run change handler before it was registered")
            return
        }
        changeHandler()
    }

    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void) {
        contactStoreForLargeRequests.requestAccess(for: .contacts, completionHandler: completionHandler)
    }

    func fetchContacts() -> Result<[Contact], Error> {
        var contacts = [Contact]()
        do {
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: ContactsFrameworkContactStoreAdaptee.allowedContactKeys)
            contactFetchRequest.sortOrder = .userDefault
            try autoreleasepool {
                try contactStoreForLargeRequests.enumerateContacts(with: contactFetchRequest) { (systemContact, _) -> Void in
                    contacts.append(Contact(systemContact: systemContact))
                }
            }
        } catch let error as NSError {
            if error.domain == CNErrorDomain, error.code == CNError.Code.communicationError.rawValue {
                // this seems occur intermittently, but not uncommonly.
                Logger.warn("communication error: \(error)")
            } else {
                owsFailDebug("Failed to fetch contacts with error:\(error)")
            }
            return .error(error)
        }

        return .success(contacts)
    }

    func fetchCNContact(contactId: String) -> CNContact? {
        var result: CNContact?
        do {
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: ContactsFrameworkContactStoreAdaptee.allowedContactKeys)
            contactFetchRequest.sortOrder = .userDefault
            contactFetchRequest.predicate = CNContact.predicateForContacts(withIdentifiers: [contactId])

            try self.contactStoreForSmallRequests.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                guard result == nil else {
                    owsFailDebug("More than one contact with contact id.")
                    return
                }
                result = contact
            }
        } catch let error as NSError {
            if error.domain == CNErrorDomain && error.code == CNError.communicationError.rawValue {
                // These errors are transient and can be safely ignored.
                Logger.error("Communication error: \(error)")
                return nil
            }
            owsFailDebug("Failed to fetch contact with error:\(error)")
            return nil
        }

        return result
    }
}

@objc
public protocol SystemContactsFetcherDelegate: AnyObject {
    func systemContactsFetcher(
        _ systemContactsFetcher: SystemContactsFetcher,
        updatedContacts contacts: [Contact],
        isUserRequested: Bool
    )
    func systemContactsFetcher(
        _ systemContactsFetcher: SystemContactsFetcher,
        hasAuthorizationStatus authorizationStatus: RawContactAuthorizationStatus
    )
}

@objc
public class SystemContactsFetcher: NSObject {

    private let serialQueue = DispatchQueue(label: "org.signal.contacts.system-fetcher")

    var lastContactUpdateHash: Int?
    var lastDelegateNotificationDate: Date?
    let contactStoreAdapter: ContactsFrameworkContactStoreAdaptee

    @objc
    public weak var delegate: SystemContactsFetcherDelegate?

    @objc
    public var rawAuthorizationStatus: RawContactAuthorizationStatus {
        return contactStoreAdapter.rawAuthorizationStatus
    }

    @objc
    public private(set) var systemContactsHaveBeenRequestedAtLeastOnce = false
    private var hasSetupObservation = false

    @objc
    public override init() {
        self.contactStoreAdapter = ContactsFrameworkContactStoreAdaptee()

        super.init()

        SwiftSingletons.register(self)
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
        guard !CurrentAppContext().isNSE else {
            let error = OWSAssertionError("Skipping contacts fetch in NSE.")
            completion(error)
            return
        }
        guard !systemContactsHaveBeenRequestedAtLeastOnce else {
            completion(nil)
            return
        }
        setupObservationIfNecessary()

        switch rawAuthorizationStatus {
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
            Logger.debug("contacts were \(rawAuthorizationStatus)")
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: rawAuthorizationStatus)
            completion(nil)
        }
    }

    @objc
    public func fetchOnceIfAlreadyAuthorized() {
        AssertIsOnMainThread()

        guard !CurrentAppContext().isNSE else {
            Logger.info("Skipping contacts fetch in NSE.")
            return
        }
        guard rawAuthorizationStatus == .authorized else {
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: rawAuthorizationStatus)
            return
        }
        guard !systemContactsHaveBeenRequestedAtLeastOnce else {
            return
        }

        updateContacts(isUserRequested: false, completion: nil)
    }

    @objc
    public func userRequestedRefresh(completion: @escaping (Error?) -> Void) {
        AssertIsOnMainThread()

        guard !CurrentAppContext().isNSE else {
            let error = OWSAssertionError("Skipping contacts fetch in NSE.")
            completion(error)
            return
        }
        guard rawAuthorizationStatus == .authorized else {
            owsFailDebug("should have already requested contact access")
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: rawAuthorizationStatus)
            completion(nil)
            return
        }

        updateContacts(isUserRequested: true, completion: completion)
    }

    @objc
    public func refreshAfterContactsChange() {
        AssertIsOnMainThread()

        guard !CurrentAppContext().isNSE else {
            Logger.info("Skipping contacts fetch in NSE.")
            return
        }
        guard rawAuthorizationStatus == .authorized else {
            Logger.info("ignoring contacts change; no access.")
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: rawAuthorizationStatus)
            return
        }

        updateContacts(isUserRequested: false, completion: nil)
    }

    private func updateContacts(
        isUserRequested: Bool = false,
        completion completionParam: ((Error?) -> Void)?
    ) {
        AssertIsOnMainThread()

        guard !CurrentAppContext().isNSE else {
            let error = OWSAssertionError("Skipping contacts fetch in NSE.")
            DispatchMainThreadSafe({
                completionParam?(error)
            })
            return
        }

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)", completionBlock: { [weak self] status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }

            guard self != nil else {
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

            let contacts: [Contact]
            switch self.contactStoreAdapter.fetchContacts() {
            case .success(let result):
                contacts = result
            case .error(let error):
                completion(error)
                return
            }

            var contactsHash = 0
            for contact in contacts {
                contactsHash = contactsHash ^ contact.hash
            }

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
        guard rawAuthorizationStatus == .authorized else {
            Logger.error("contact fetch failed; no access.")
            return nil
        }

        return contactStoreAdapter.fetchCNContact(contactId: contactId)
    }
}
