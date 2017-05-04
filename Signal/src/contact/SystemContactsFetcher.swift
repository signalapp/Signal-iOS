//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import Contacts

@objc protocol SystemContactsFetcherDelegate: class {
    func systemContactsFetcher(_ systemContactsFetcher: SystemContactsFetcher, updatedContacts contacts: [Contact])
}

@objc
class SystemContactsFetcher: NSObject {

    private let TAG = "[SystemContactsFetcher]"

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
        CNContactEmailAddressesKey as CNKeyDescriptor
    ]

    public func requestOnce() {
        AssertIsOnMainThread()

        guard !systemContactsHaveBeenRequestedAtLeastOnce else {
            Logger.debug("\(TAG) already requested system contacts")
            return
        }
        systemContactsHaveBeenRequestedAtLeastOnce = true
        self.startObservingContactChanges()

        switch authorizationStatus {
        case .notDetermined:
            contactStore.requestAccess(for: .contacts, completionHandler: { (granted, error) in
                if let error = error {
                    Logger.error("\(self.TAG) error fetching contacts: \(error)")
                    assertionFailure()
                }

                if !granted {
                    // TODO, make this a one time dismissable admonishment
                    // e.g. remember across launches that the user has dismissed.
                    self.displayMissingContactsPermissionAlert()
                } else {
                    self.updateContacts()
                }
            })
        case .authorized:
            // TODO reset onetime admonishment reminder, so that we remind user again (once) if they've since toggled permissions.
            self.updateContacts()
        case .denied, .restricted:
            Logger.debug("\(TAG) contacts were \(self.authorizationStatus)")
        }
    }

    public func fetchIfAlreadyAuthorized() {
        AssertIsOnMainThread()
        guard authorizationStatus == .authorized else {
            return
        }

        updateContacts()
    }

    private func displayMissingContactsPermissionAlert() {
        let foo = UIApplication.shared.frontmostViewController
        Logger.error("TODO")
    }

    private func updateContacts() {
        systemContactsHaveBeenRequestedAtLeastOnce = true

        var systemContacts = [CNContact]()
        do {
            let contactFetchRequest = CNContactFetchRequest(keysToFetch: allowedContactKeys)
            try contactStore.enumerateContacts(with: contactFetchRequest) { (contact, _) -> Void in
                systemContacts.append(contact)
            }
        } catch let error as NSError {
            Logger.error("\(self.TAG) Failed to fetch contacts with error:\(error)")
            assertionFailure()
        }

        let contacts = systemContacts.map { Contact(systemContact: $0) }
        self.delegate?.systemContactsFetcher(self, updatedContacts: contacts)
    }

    private func startObservingContactChanges() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(contactStoreDidChange),
            name: .CNContactStoreDidChange,
            object: nil)
    }

    @objc
    private func contactStoreDidChange() {
        updateContacts()
    }

}
