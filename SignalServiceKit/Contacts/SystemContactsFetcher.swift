//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import Contacts
import ContactsUI

protocol ContactStoreAdaptee {
    var rawAuthorizationStatus: RawContactAuthorizationStatus { get }
    func requestAccess(completionHandler: @escaping (Bool, Error?) -> Void)
    func fetchContacts() -> Result<[SystemContact], Error>
    func fetchCNContact(contactId: String) -> CNContact?
    func startObservingChanges(changeHandler: @escaping () -> Void)
}

public class ContactsFrameworkContactStoreAdaptee: NSObject, ContactStoreAdaptee {
    private let contactStoreForLargeRequests = CNContactStore()
    private let contactStoreForSmallRequests = CNContactStore()
    private var changeHandler: (() -> Void)?
    private var initializedObserver = false
    private var lastSortOrder: CNContactSortOrder?

    private let appReadiness: AppReadiness

    init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        super.init()
    }

    private static let discoveryContactKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]

    public static let fullContactKeys: [CNKeyDescriptor] = ContactsFrameworkContactStoreAdaptee.discoveryContactKeys + [
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor, // TODO full image instead of thumbnail?
        CNContactViewController.descriptorForRequiredKeys(),
        CNContactVCardSerialization.descriptorForRequiredKeys()
    ]

    var rawAuthorizationStatus: RawContactAuthorizationStatus {
        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        switch authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .limited:
            return .limited
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
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
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

    func fetchContacts() -> Result<[SystemContact], Error> {
        do {
            var contacts = [SystemContact]()
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: Self.discoveryContactKeys)
            contactFetchRequest.sortOrder = .userDefault
            try autoreleasepool {
                try contactStoreForLargeRequests.enumerateContacts(with: contactFetchRequest) { (systemContact, _) -> Void in
                    contacts.append(SystemContact(cnContact: systemContact, didFetchEmailAddresses: false))
                }
            }
            return .success(contacts)
        } catch {
            switch error {
            case CNError.communicationError:
                // this seems occur intermittently, but not uncommonly.
                Logger.warn("communication error: \(error)")
            default:
                owsFailDebug("Failed to fetch contacts with error:\(error)")
            }
            return .failure(error)
        }
    }

    func fetchCNContact(contactId: String) -> CNContact? {
        do {
            owsAssertDebug(!CurrentAppContext().isNSE)
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: ContactsFrameworkContactStoreAdaptee.fullContactKeys)
            contactFetchRequest.sortOrder = .userDefault
            contactFetchRequest.predicate = CNContact.predicateForContacts(withIdentifiers: [contactId])

            var result: CNContact?
            try self.contactStoreForSmallRequests.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                guard result == nil else {
                    owsFailDebug("More than one contact with contact id.")
                    return
                }
                result = contact
            }
            return result
        } catch CNError.communicationError {
            // These errors are transient and can be safely ignored.
            Logger.error("Communication error")
            return nil
        } catch {
            owsFailDebug("Failed to fetch contact with error:\(error)")
            return nil
        }
    }
}

protocol SystemContactsFetcherDelegate: AnyObject {
    func systemContactsFetcher(
        _ systemContactsFetcher: SystemContactsFetcher,
        updatedContacts contacts: [SystemContact],
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

    weak var delegate: SystemContactsFetcherDelegate?

    @objc
    public var rawAuthorizationStatus: RawContactAuthorizationStatus {
        return contactStoreAdapter.rawAuthorizationStatus
    }

    public var canReadSystemContacts: Bool {
        switch rawAuthorizationStatus {
        case .notDetermined, .denied, .restricted:
            return false
        case .limited, .authorized:
            return true
        }
    }

    public private(set) var systemContactsHaveBeenRequestedAtLeastOnce = false
    private var hasSetupObservation = false

    public init(appReadiness: AppReadiness) {
        self.contactStoreAdapter = ContactsFrameworkContactStoreAdaptee(appReadiness: appReadiness)

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
        case .authorized, .limited:
            self.updateContacts(completion: completion)
        case .denied, .restricted:
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
        guard canReadSystemContacts else {
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

        switch rawAuthorizationStatus {
        case .notDetermined, .denied, .restricted:
            owsFailDebug("should have already requested contact access")
            self.delegate?.systemContactsFetcher(self, hasAuthorizationStatus: rawAuthorizationStatus)
            completion(nil)
            return
        case .limited, .authorized:
            break
        }

        updateContacts(isUserRequested: true, completion: completion)
    }

    public func refreshAfterContactsChange() {
        AssertIsOnMainThread()

        guard !CurrentAppContext().isNSE else {
            Logger.info("Skipping contacts fetch in NSE.")
            return
        }
        guard canReadSystemContacts else {
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
            Logger.info("Fetching contacts")

            let contacts: [SystemContact]
            switch self.contactStoreAdapter.fetchContacts() {
            case .success(let result):
                contacts = result
            case .failure(let error):
                completion(error)
                return
            }

            var hasher = Hasher()
            for contact in contacts {
                hasher.combine(contact.computeSystemContactHashValue())
            }
            let contactsHash = hasher.finalize()

            DispatchQueue.main.async {
                var shouldNotifyDelegate = false

                // If nothing has changed, only notify delegate (to perform contact intersection) every N hours
                let kDebounceInterval = 12 * kHourInterval

                if self.lastContactUpdateHash != contactsHash {
                    Logger.info("Updating contacts because hash changed")
                    shouldNotifyDelegate = true
                } else if isUserRequested {
                    Logger.info("Updating contacts because of user request")
                    shouldNotifyDelegate = true
                } else if
                    let lastDelegateNotificationDate = self.lastDelegateNotificationDate,
                    -lastDelegateNotificationDate.timeIntervalSinceNow > kDebounceInterval
                {
                    Logger.info("Updating contacts because it's been more than \(kDebounceInterval) seconds")
                    shouldNotifyDelegate = true
                }

                if shouldNotifyDelegate {
                    self.lastContactUpdateHash = contactsHash
                    self.lastDelegateNotificationDate = Date()
                    self.delegate?.systemContactsFetcher(self, updatedContacts: contacts, isUserRequested: isUserRequested)
                }
                completion(nil)
            }
        }
    }

    @objc
    public func fetchCNContact(contactId: String) -> CNContact? {
        guard canReadSystemContacts else {
            Logger.error("contact fetch failed; no access.")
            return nil
        }

        return contactStoreAdapter.fetchCNContact(contactId: contactId)
    }
}
