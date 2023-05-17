//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit

public struct UsernameQuerier {
    private let contactsManager: ContactsManagerProtocol
    private let databaseStorage: SDSDatabaseStorage
    private let networkManager: NetworkManager
    private let profileManager: ProfileManagerProtocol
    private let recipientFetcher: RecipientFetcher
    private let schedulers: Schedulers
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager
    private let usernameLookupManager: UsernameLookupManager

    public init(
        contactsManager: ContactsManagerProtocol,
        databaseStorage: SDSDatabaseStorage,
        networkManager: NetworkManager,
        profileManager: ProfileManagerProtocol,
        recipientFetcher: RecipientFetcher,
        schedulers: Schedulers,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager,
        usernameLookupManager: UsernameLookupManager
    ) {
        self.contactsManager = contactsManager
        self.databaseStorage = databaseStorage
        self.networkManager = networkManager
        self.profileManager = profileManager
        self.recipientFetcher = recipientFetcher
        self.schedulers = schedulers
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.usernameLookupManager = usernameLookupManager
    }

    /// Query the service for the given username, invoking a callback if the
    /// username is successfully resolved to an ACI.
    ///
    /// - Parameter onSuccess
    /// A callback invoked if the queried username resolves to an ACI.
    /// Guaranteed to be called on the main thread.
    public func queryForUsername(
        username: String,
        fromViewController: UIViewController,
        onSuccess: @escaping (ServiceId) -> Void
    ) {
        if let localAciToReturn = databaseStorage.read(block: { tx in
            isOwnUsername(username: username, tx: tx)
        }) {
            // Queried for ourselves, no need to hit the service.
            onSuccess(localAciToReturn)
            return
        }

        if let hashedUsername = try? Usernames.HashedUsername(forUsername: username) {
            queryServiceForUsernameBehindSpinner(
                hashedUsername: hashedUsername,
                fromViewController: fromViewController,
                onSuccess: onSuccess
            )
        } else {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "USERNAME_LOOKUP_INVALID_USERNAME_TITLE",
                    comment: "Title for an action sheet indicating that a user-entered username value is not a valid username."
                ),
                message: String(
                    format: OWSLocalizedString(
                        "USERNAME_LOOKUP_INVALID_USERNAME_MESSAGE_FORMAT",
                        comment: "A message indicating that a user-entered username value is not a valid username. Embeds {{ a username }}."
                    ),
                    username
                )
            )
        }
    }

    /// If the given username refers to the local user, returns the local ACI.
    /// Otherwise, returns `nil`.
    private func isOwnUsername(username: String, tx: SDSAnyReadTransaction) -> ServiceId? {
        guard let localAci = tsAccountManager.localIdentifiers(transaction: tx)?.aci else {
            owsFailDebug("Missing local ACI!")
            return nil
        }

        let localUsername = usernameLookupManager.fetchUsername(
            forAci: localAci,
            transaction: tx.asV2Read
        )

        if localUsername?.caseInsensitiveCompare(username) == .orderedSame {
            return localAci
        }

        return nil
    }

    /// Query the service for the ACI of the given username, while presenting a
    /// modal activity indicator.
    ///
    /// - Parameter onSuccess
    /// Called if the username resolves successfully to an ACI. Guaranteed to be
    /// called on the main thread.
    private func queryServiceForUsernameBehindSpinner(
        hashedUsername: Usernames.HashedUsername,
        fromViewController: UIViewController,
        onSuccess: @escaping (ServiceId) -> Void
    ) {
        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: true
        ) { modal in
            firstly(on: schedulers.sync) { () -> Promise<ServiceId?> in
                return Usernames.API(
                    networkManager: self.networkManager,
                    schedulers: self.schedulers
                )
                .attemptAciLookup(forHashedUsername: hashedUsername)
            }.done(on: schedulers.main) { maybeAci in
                modal.dismissIfNotCanceled {
                    if let aci = maybeAci {
                        self.databaseStorage.write { tx in
                            self.handleUsernameLookupCompleted(
                                aci: aci,
                                username: hashedUsername.usernameString,
                                tx: tx
                            )
                        }

                        schedulers.main.async {
                            onSuccess(aci)
                        }
                    } else {
                        OWSActionSheets.showActionSheet(
                            title: OWSLocalizedString(
                                "USERNAME_LOOKUP_NOT_FOUND_TITLE",
                                comment: "Title for an action sheet indicating that the given username is not associated with a registered Signal account."
                            ),
                            message: String(
                                format: OWSLocalizedString(
                                    "USERNAME_LOOKUP_NOT_FOUND_MESSAGE_FORMAT",
                                    comment: "A message indicating that the given username is not associated with a registered Signal account. Embeds {{ a username }}."
                                ),
                                hashedUsername.usernameString
                            )
                        )
                    }
                }
            }.catch(on: schedulers.main) { _ in
                Logger.error("Error while querying for username!")

                modal.dismissIfNotCanceled {
                    OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                        "USERNAME_LOOKUP_ERROR_MESSAGE",
                        comment: "A message indicating that username lookup failed."
                    ))
                }
            }
        }
    }

    private func handleUsernameLookupCompleted(
        aci: ServiceId,
        username: String,
        tx: SDSAnyWriteTransaction
    ) {
        let recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx.asV2Write)
        recipient.markAsRegistered(transaction: tx)

        let isUsernameBestIdentifier = Usernames.BetterIdentifierChecker.assembleByQuerying(
            forRecipient: recipient,
            profileManager: profileManager,
            contactManager: contactsManager,
            transaction: tx
        ).usernameIsBestIdentifier()

        if isUsernameBestIdentifier {
            // If this username is the best identifier we have for this
            // address, we should save it locally and in StorageService.

            usernameLookupManager.saveUsername(
                username,
                forAci: aci,
                transaction: tx.asV2Write
            )

            storageServiceManager.recordPendingUpdates(updatedAccountIds: [recipient.accountId])
        } else {
            // If we have a better identifier for this address, we can
            // throw away any stored username info for it.

            usernameLookupManager.saveUsername(
                nil,
                forAci: aci,
                transaction: tx.asV2Write
            )
        }
    }
}
